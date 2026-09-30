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
        containsAll(['users', 'sessions', 'baselines', 'engine_states', 'reports']),
      );
    });

    test('stores and reads back a user', () async {
      await db.into(db.users).insert(
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

    test('foreign keys are enforced, so an orphan session cannot be written',
        () async {
      // Drift leaves foreign keys off by default, which would make the references
      // in the schema documentation rather than constraints.
      await expectLater(
        db.into(db.sessions).insert(
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
    });

    test('deleting a user takes their sessions with them', () async {
      // Account deletion has to leave nothing behind; relying on application code
      // to delete each table in the right order is how rows get orphaned.
      await db.into(db.users).insert(
            UsersCompanion.insert(
              id: 'user-1',
              createdAt: DateTime.utc(2026, 3, 14, 9),
            ),
          );
      await db.into(db.sessions).insert(
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

      await db.delete(db.users).delete(
            const UsersCompanion(id: Value('user-1')),
          );

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
      final cipherVersion =
          database.select('PRAGMA cipher_version').singleOrNull;
      expect(
        cipherVersion,
        isNotNull,
        reason: 'PRAGMA cipher_version returned nothing, so this is plain '
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
              setup: (database) =>
                  database.execute('PRAGMA key = "x\'$key\'"'),
            ),
          );

      final first = openDrift();
      await first.into(first.users).insert(
            UsersCompanion.insert(
              id: 'user-1',
              createdAt: DateTime.utc(2026, 3, 14, 9),
              displayName: const Value('Test User'),
            ),
          );
      await first.close();

      final second = openDrift();
      addTearDown(second.close);
      expect((await second.select(second.users).getSingle()).displayName,
          'Test User');

      final asText = String.fromCharCodes(
        file.readAsBytesSync().where((byte) => byte >= 32 && byte < 127),
      );
      expect(asText, isNot(contains('Test User')));
    });
  });
}
