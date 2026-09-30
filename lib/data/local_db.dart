/// The encrypted local database.
///
/// Everything the app knows lives here first. The network is only ever a backup,
/// and a session that cannot be uploaded is still a session the user can see --
/// which is what "offline-first" has to mean for an app used on a patchy
/// connection.
///
/// Encryption is SQLCipher with a key generated once and kept in the platform
/// keystore, never in the database file and never in the source. A lost or stolen
/// phone is the threat this addresses: the OS lock screen is the first barrier and
/// this is the second.
///
/// SQLCipher is selected in `pubspec.yaml` under `hooks.user_defines.sqlite3`
/// rather than by a plugin package. Since `package:sqlite3` version 3 the library
/// is fetched by that package's build hook, so there is no `open()` override here
/// and no `sqlcipher_flutter_libs` dependency -- both of which older guides still
/// describe, and neither of which works any more.
library;

import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'local_db.g.dart';

/// Where the SQLCipher key is kept.
///
/// `flutter_secure_storage` maps to the Android Keystore and the iOS Keychain, so
/// the key is held by the OS rather than by the app, and is destroyed with the
/// app's data when the account is deleted.
const _keyStorageName = 'neurascan_db_key';

/// Length of the generated key, in bytes. Thirty-two bytes is AES-256, and hex
/// encodes to the 64 characters SQLCipher expects for a raw key.
const _keyBytes = 32;

/// Database file name.
const _databaseFile = 'neurascan.db';

/// The users table.
///
/// One row in normal use, but not enforced as one: a community health worker may
/// run sessions for several people on a shared phone, which is listed as a
/// real-world application of the project.
@DataClassName('UserRow')
class Users extends Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get email => text().nullable()();
  TextColumn get displayName => text().nullable()();
  TextColumn get dominantHand => text().withDefault(const Constant('right'))();
  TextColumn get languageCode => text().withDefault(const Constant('en'))();

  /// Consent as JSON, so that adding a field to the consent record does not need
  /// a schema migration. Consent is read rarely and always as a whole.
  TextColumn get consentJson => text().nullable()();

  BoolColumn get reminderEnabled =>
      boolean().withDefault(const Constant(true))();
  IntColumn get reminderIntervalDays =>
      integer().withDefault(const Constant(2))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One row per completed session attempt, including invalid and confounded ones.
///
/// Invalid sessions are kept rather than discarded so that the user can see that
/// an attempt happened, and so that the familiarisation count stays reproducible
/// if the engine state ever has to be rebuilt by replaying history.
@DataClassName('SessionRow')
class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get userId =>
      text().references(Users, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime()();

  /// The check-in answers as JSON.
  TextColumn get checkInJson => text()();

  /// The nine derived features as JSON. An empty object for an invalid session.
  TextColumn get featuresJson => text()();

  BoolColumn get valid => boolean()();
  TextColumn get status => text()();
  TextColumn get invalidReasonsJson =>
      text().withDefault(const Constant('[]'))();

  RealColumn get deviationIndex => real().nullable()();
  RealColumn get ewma => real().nullable()();
  IntColumn get runLength => integer().nullable()();
  TextColumn get domainScoresJson => text().nullable()();
  TextColumn get contributionsJson => text().nullable()();

  /// Recalled and missed words. Local only; never part of the sync payload.
  TextColumn get recallDetailJson => text().nullable()();

  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The frozen baseline, one row per user.
///
/// Stored apart from the sessions it came from so that it is unmistakably a frozen
/// artefact: recomputing it is an explicit action, never a side effect of a new
/// session arriving.
@DataClassName('BaselineRow')
class Baselines extends Table {
  TextColumn get userId =>
      text().references(Users, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get frozenAt => dateTime()();
  TextColumn get medianJson => text()();
  TextColumn get scaleJson => text()();
  IntColumn get sessionCount => integer()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

/// The engine's smoothing state, one row per user.
///
/// Persisted rather than recomputed on every launch. Replaying history would give
/// the same answer today, but it would also mean that deleting one old session
/// silently changed the current status, which is not what a user deleting a single
/// bad session would expect.
@DataClassName('EngineStateRow')
class EngineStates extends Table {
  TextColumn get userId =>
      text().references(Users, #id, onDelete: KeyAction.cascade)();
  RealColumn get ewma => real().withDefault(const Constant(0.0))();
  IntColumn get runLength => integer().withDefault(const Constant(0))();
  IntColumn get sessionsSeen => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

/// Exported PDF reports, so the user can see what they have already shared.
///
/// The PDF itself stays on the phone; only the fact that a report was produced,
/// and what it said, is recorded.
@DataClassName('ReportRow')
class Reports extends Table {
  TextColumn get id => text()();
  TextColumn get userId =>
      text().references(Users, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get periodStart => dateTime()();
  DateTimeColumn get periodEnd => dateTime()();
  TextColumn get status => text()();
  TextColumn get contributionsJson => text()();
  IntColumn get sessionCount => integer()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Users, Sessions, Baselines, EngineStates, Reports])
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase(super.executor);

  /// Opens the real, encrypted database on the device.
  factory LocalDatabase.encrypted() => LocalDatabase(_openEncrypted());

  /// An unencrypted in-memory database, for tests.
  ///
  /// Named so that it cannot be mistaken for the production opener at a glance: a
  /// test database that silently became the real one would drop encryption
  /// without anything failing.
  factory LocalDatabase.forTesting() => LocalDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      // Drift does not enable foreign keys by default; without this the
      // references declared above would be documentation rather than
      // constraints, and deleting a user would leave their sessions behind.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

/// Opens the database file with SQLCipher, fetching the key first.
///
/// [LazyDatabase] exists for exactly this: the key has to be read from the
/// platform keystore, which is asynchronous, but SQLCipher's `PRAGMA key` has to
/// run synchronously in the connection setup.
QueryExecutor _openEncrypted() => LazyDatabase(() async {
  final key = await obtainDatabaseKey();
  final directory = await getApplicationDocumentsDirectory();
  final file = File(p.join(directory.path, _databaseFile));

  return NativeDatabase(
    file,
    setup: (database) {
      // The x'...' form supplies the key material directly instead of running
      // it through SQLCipher's key derivation. That is the right choice here
      // because the key is already 32 bytes from a cryptographic generator;
      // derivation exists to stretch a user-chosen passphrase, which this is
      // not. The value is generated hex, so it cannot break out of the quotes.
      database.execute('PRAGMA key = "x\'$key\'"');

      // Fails loudly if the key is wrong rather than on the first query,
      // which would be reported as a corrupt database.
      database.execute('SELECT count(*) FROM sqlite_master');
    },
  );
});

/// Returns the SQLCipher key, generating and storing one on first run.
///
/// Kept separate from the database so that the key's whole lifecycle is visible in
/// one place: created once, read on every open, and deleted only when the user
/// deletes their account. No other code path writes it anywhere.
Future<String> obtainDatabaseKey({FlutterSecureStorage? storage}) async {
  final secureStorage = storage ?? const FlutterSecureStorage();
  final existing = await secureStorage.read(key: _keyStorageName);
  if (existing != null && existing.length == _keyBytes * 2) return existing;

  final generated = generateDatabaseKey();
  await secureStorage.write(key: _keyStorageName, value: generated);
  return generated;
}

/// Deletes the database key.
///
/// Called as part of account deletion. Once the key is gone the database file is
/// unreadable even if a copy survives in a device backup, which is the point of
/// deleting the key rather than only the rows.
Future<void> destroyDatabaseKey({FlutterSecureStorage? storage}) async {
  final secureStorage = storage ?? const FlutterSecureStorage();
  await secureStorage.delete(key: _keyStorageName);
}

/// Generates a fresh 256-bit key, hex encoded.
///
/// [Random.secure] rather than [Random]: the default generator is seeded
/// predictably enough that a key from it would not be worth encrypting with.
String generateDatabaseKey() {
  final random = Random.secure();
  return List<int>.generate(
    _keyBytes,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
