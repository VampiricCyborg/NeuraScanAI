/// The local database schema, and the encryption that protects it.
///
/// The encryption test is the important one here. Everything else in the privacy
/// story is a claim about code that could be checked by reading it; "the database
/// file is unreadable without the key" is a claim about a file on disk, and the
/// only way to be sure of it is to try.
library;

import 'dart:io';

// drift exports `isNull`/`isNotNull` as SQL expression helpers, which collide with
// the matchers of the same name.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/data/local_db.dart';
import 'package:neurascan_ai/data/repository.dart';
import 'package:neurascan_ai/data/sync_service.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('schema', () {
    late LocalDatabase db;

    setUp(() => db = LocalDatabase.forTesting());
    tearDown(() => db.close());

    test('opens and creates every table', () async {
      final names = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final tables = names.map((row) => row.read<String>('name')).toSet();

      expect(
        tables,
        containsAll([
          'users',
          'sessions',
          'baselines',
          'engine_states',
          'reports',
        ]),
      );
    });

    test('stores and reads back a user', () async {
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              id: 'user-1',
              createdAt: DateTime.utc(2026, 3, 14, 9),
              email: const Value('someone@example.com'),
            ),
          );

      final stored = await db.select(db.users).getSingle();
      expect(stored.id, 'user-1');
      expect(stored.email, 'someone@example.com');
      // Defaults matter: a user created before ever reaching the settings screen
      // must still get a usable reminder cadence and language.
      expect(stored.dominantHand, 'right');
      expect(stored.languageCode, 'en');
      expect(stored.reminderEnabled, isTrue);
      expect(stored.reminderIntervalDays, 2);
    });

    test(
      'foreign keys are enforced, so an orphan session cannot be written',
      () async {
        // Drift leaves foreign keys off by default, which would make the references
        // in the schema documentation rather than constraints.
        await expectLater(
          db
              .into(db.sessions)
              .insert(
                SessionsCompanion.insert(
                  id: 'session-1',
                  userId: 'nobody',
                  startedAt: DateTime.utc(2026, 3, 14, 9),
                  completedAt: DateTime.utc(2026, 3, 14, 9, 4),
                  checkInJson: '{}',
                  featuresJson: '{}',
                  valid: true,
                  status: 'STABLE',
                ),
              ),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test('deleting a user takes their sessions with them', () async {
      // Account deletion has to leave nothing behind; relying on application code
      // to delete each table in the right order is how rows get orphaned.
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              id: 'user-1',
              createdAt: DateTime.utc(2026, 3, 14, 9),
            ),
          );
      await db
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: 'session-1',
              userId: 'user-1',
              startedAt: DateTime.utc(2026, 3, 14, 9),
              completedAt: DateTime.utc(2026, 3, 14, 9, 4),
              checkInJson: '{}',
              featuresJson: '{}',
              valid: true,
              status: 'STABLE',
            ),
          );

      await db
          .delete(db.users)
          .delete(const UsersCompanion(id: Value('user-1')));

      expect(await db.select(db.sessions).get(), isEmpty);
    });
  });

  group('database key', () {
    test('is 256 bits, hex encoded', () {
      final key = generateDatabaseKey();
      expect(key, hasLength(64));
      expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('is different every time', () {
      final keys = {for (var i = 0; i < 50; i++) generateDatabaseKey()};
      expect(keys, hasLength(50));
    });
  });

  group('encryption', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('neurascan_cipher_test');
    });
    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    /// Writes a small encrypted database and returns its file.
    File writeEncrypted(String key) {
      final file = File('${directory.path}/encrypted.db');
      final database = sqlite3.open(file.path)
        ..execute('PRAGMA key = "x\'$key\'"')
        ..execute('CREATE TABLE secrets (note TEXT)')
        ..execute("INSERT INTO secrets VALUES ('delayed recall 0.75')");
      database.close();
      return file;
    }

    test('SQLCipher is actually the library that got built', () {
      // If pubspec's hooks.user_defines selected plain SQLite, `PRAGMA key` is
      // silently accepted and does nothing -- the worst possible failure, because
      // the app would report itself as encrypted while writing plaintext. So this
      // asserts on the built library rather than trusting the configuration.
      expect(
        sqlite3.version.libVersion,
        isNotEmpty,
        reason: 'no sqlite3 library was loaded at all',
      );

      final database = sqlite3.openInMemory();
      addTearDown(database.close);
      final cipherVersion = database
          .select('PRAGMA cipher_version')
          .singleOrNull;
      expect(
        cipherVersion,
        isNotNull,
        reason:
            'PRAGMA cipher_version returned nothing, so this is plain '
            'SQLite and the local database would not be encrypted',
      );
    });

    test('the file on disk does not contain the plaintext', () {
      final file = writeEncrypted(generateDatabaseKey());
      final bytes = file.readAsBytesSync();
      final asText = String.fromCharCodes(
        bytes.where((byte) => byte >= 32 && byte < 127),
      );

      expect(asText, isNot(contains('delayed recall')));
      expect(asText, isNot(contains('secrets')));
      // A plain SQLite file starts with this string; an encrypted one does not.
      expect(asText, isNot(startsWith('SQLite format 3')));
    });

    test('the right key opens it', () {
      final key = generateDatabaseKey();
      final file = writeEncrypted(key);

      final reopened = sqlite3.open(file.path)
        ..execute('PRAGMA key = "x\'$key\'"');
      addTearDown(reopened.close);

      expect(
        reopened.select('SELECT note FROM secrets').single['note'],
        'delayed recall 0.75',
      );
    });

    test('the wrong key does not', () {
      final file = writeEncrypted(generateDatabaseKey());
      final wrongKey = generateDatabaseKey();

      final reopened = sqlite3.open(file.path)
        ..execute('PRAGMA key = "x\'$wrongKey\'"');
      addTearDown(reopened.close);

      expect(
        () => reopened.select('SELECT note FROM secrets'),
        throwsA(isA<SqliteException>()),
      );
    });

    test('no key at all does not', () {
      final file = writeEncrypted(generateDatabaseKey());

      final reopened = sqlite3.open(file.path);
      addTearDown(reopened.close);

      expect(
        () => reopened.select('SELECT note FROM secrets'),
        throwsA(isA<SqliteException>()),
      );
    });

    test('drift can use an encrypted file end to end', () async {
      final key = generateDatabaseKey();
      final file = File('${directory.path}/drift.db');

      LocalDatabase openDrift() => LocalDatabase(
        NativeDatabase(
          file,
          setup: (database) => database.execute('PRAGMA key = "x\'$key\'"'),
        ),
      );

      final first = openDrift();
      await first
          .into(first.users)
          .insert(
            UsersCompanion.insert(
              id: 'user-1',
              createdAt: DateTime.utc(2026, 3, 14, 9),
              displayName: const Value('Test User'),
            ),
          );
      await first.close();

      final second = openDrift();
      addTearDown(second.close);
      expect(
        (await second.select(second.users).getSingle()).displayName,
        'Test User',
      );

      final asText = String.fromCharCodes(
        file.readAsBytesSync().where((byte) => byte >= 32 && byte < 127),
      );
      expect(asText, isNot(contains('Test User')));
    });
  });

  group('migration from version 1', () {
    // Version 1 measured nine things in four areas. A phone that ran it holds a baseline and
    // tests that cannot be compared with the five measurements in three areas that replaced
    // them, so the upgrade moves the user to a new baseline and keeps what they had.
    late LocalDatabase db;

    /// A database exactly as version 1 left it, with one user, one stored test from the old
    /// four-area design, a frozen baseline and an engine state.
    LocalDatabase openVersionOne() => LocalDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw
            ..execute(
              'CREATE TABLE users ('
              'id TEXT NOT NULL PRIMARY KEY, created_at INTEGER NOT NULL, '
              'email TEXT NULL, display_name TEXT NULL, '
              "dominant_hand TEXT NOT NULL DEFAULT 'right', "
              "language_code TEXT NOT NULL DEFAULT 'en', consent_json TEXT NULL, "
              'reminder_enabled INTEGER NOT NULL DEFAULT 1, '
              'reminder_interval_days INTEGER NOT NULL DEFAULT 2)',
            )
            ..execute(
              'CREATE TABLE sessions ('
              'id TEXT NOT NULL PRIMARY KEY, user_id TEXT NOT NULL, '
              'started_at INTEGER NOT NULL, completed_at INTEGER NOT NULL, '
              'check_in_json TEXT NOT NULL, features_json TEXT NOT NULL, '
              'valid INTEGER NOT NULL, status TEXT NOT NULL, '
              "invalid_reasons_json TEXT NOT NULL DEFAULT '[]', "
              'deviation_index REAL NULL, ewma REAL NULL, run_length INTEGER NULL, '
              'domain_scores_json TEXT NULL, contributions_json TEXT NULL, '
              'recall_detail_json TEXT NULL, synced INTEGER NOT NULL DEFAULT 0)',
            )
            ..execute(
              'CREATE TABLE baselines ('
              'user_id TEXT NOT NULL PRIMARY KEY, frozen_at INTEGER NOT NULL, '
              'median_json TEXT NOT NULL, scale_json TEXT NOT NULL, '
              'session_count INTEGER NOT NULL)',
            )
            ..execute(
              'CREATE TABLE engine_states ('
              'user_id TEXT NOT NULL PRIMARY KEY, '
              'ewma REAL NOT NULL DEFAULT 0.0, run_length INTEGER NOT NULL DEFAULT 0, '
              'sessions_seen INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL)',
            )
            ..execute(
              'CREATE TABLE reports ('
              'id TEXT NOT NULL PRIMARY KEY, user_id TEXT NOT NULL, '
              'created_at INTEGER NOT NULL, period_start INTEGER NOT NULL, '
              'period_end INTEGER NOT NULL, status TEXT NOT NULL, '
              'contributions_json TEXT NOT NULL, session_count INTEGER NOT NULL, '
              'synced INTEGER NOT NULL DEFAULT 0)',
            )
            ..execute(
              "INSERT INTO users (id, created_at) VALUES ('user-1', 1700000000)",
            )
            ..execute(
              'INSERT INTO sessions (id, user_id, started_at, completed_at, '
              'check_in_json, features_json, valid, status, domain_scores_json, '
              'contributions_json) VALUES ('
              "'old-1', 'user-1', 1700000000, 1700000240, "
              '\'{"sleep":"good","fatigue":"none","illnessOrMedicationChange":false,'
              '"answeredAt":"2023-11-14T22:13:20.000Z"}\', '
              '\'{"delayed_recall":0.7,"reaction_median":320.0}\', 1, \'STABLE\', '
              '\'{"cognitive":0.1,"speech":0.2,"motor":0.0,"interaction":0.4}\', '
              '\'{"cognitive":0.2,"speech":0.2,"motor":0.1,"interaction":0.5}\')',
            )
            ..execute(
              'INSERT INTO baselines VALUES '
              "('user-1', 1700000000, '{}', '{}', 3)",
            )
            ..execute(
              "INSERT INTO engine_states VALUES ('user-1', 0.4, 1, 6, 1700000000)",
            )
            ..execute('PRAGMA user_version = 1');
        },
      ),
    );

    setUp(() => db = openVersionOne());
    tearDown(() => db.close());

    Repository repositoryFor(LocalDatabase database) => Repository(
      database: database,
      syncQueue: SyncQueue(backend: const DisabledSyncBackend()),
    );

    test('moves the existing user to a new baseline', () async {
      final user = await db.select(db.users).getSingle();
      expect(user.baselineEpoch, 1);
    });

    test('drops the old baseline and engine state', () async {
      expect(await db.select(db.baselines).get(), isEmpty);
      expect(await db.select(db.engineStates).get(), isEmpty);
    });

    test('keeps the old tests, set aside from the new baseline', () async {
      final repository = repositoryFor(db);

      expect(await repository.loadSessions('user-1'), isEmpty);
      final all = await repository.loadSessions('user-1', allBaselines: true);
      expect(all.single.id, 'old-1');
      expect(all.single.epoch, 0);
    });

    test(
      'reads a test that has a score for an area that no longer exists',
      () async {
        final repository = repositoryFor(db);

        final old = (await repository.loadSessions(
          'user-1',
          allBaselines: true,
        )).single;
        expect(old.domainScores!.keys.map((d) => d.key).toSet(), {
          'cognitive',
          'speech',
          'motor',
        });
        expect(old.contributions, isNotNull);
      },
    );

    test('exports the old test along with the rest', () async {
      final repository = repositoryFor(db);
      await repository.ensureProfile(userId: 'user-1');

      final export = await repository.exportEverything('user-1');
      final exported = (export['sessions']! as List)
          .cast<Map<String, dynamic>>();
      expect(exported.single['id'], 'old-1');
    });

    test('the new baseline needs no practice test', () async {
      final engine = await repositoryFor(db).loadEngine('user-1');
      expect(engine.baselineReady, isFalse);
      expect(engine.sessionsSeen, kFamiliarisationSessions);
    });
  });
}
