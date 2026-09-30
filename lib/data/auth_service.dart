/// Sign-in, behind an interface.
///
/// The report specifies Firebase Authentication, and the Firebase implementation
/// lives in `firebase_auth_service.dart`. It is reached through this interface for
/// two reasons that outlive the choice of provider.
///
/// The first is that the app has to work offline, and that includes the first
/// screen. An account is a way of separating one person's baseline from another's
/// on a shared phone; it is not a licence check, and requiring a network round
/// trip to reach a screening session would make the app useless in exactly the
/// rural settings it is meant for.
///
/// The second is testability. Every screen above this line can be driven by a
/// fake, so the sign-in flow, the consent gate and the router redirects are all
/// covered by ordinary widget tests with no emulator and no test project.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Why a sign-in attempt failed.
///
/// A closed set rather than a message, so that the UI decides the wording and can
/// translate it. Provider error codes are mapped onto these.
enum AuthFailure {
  invalidCredentials,
  emailAlreadyInUse,
  weakPassword,
  invalidEmail,
  userNotFound,
  networkUnavailable,
  tooManyAttempts,
  unknown;

  /// English wording. The localised strings live with the screens; this is the
  /// fallback and what the tests assert on.
  String get message => switch (this) {
        AuthFailure.invalidCredentials =>
          'That email and password do not match an account.',
        AuthFailure.emailAlreadyInUse =>
          'There is already an account with that email address.',
        AuthFailure.weakPassword =>
          'Please choose a password of at least 8 characters.',
        AuthFailure.invalidEmail => 'That does not look like an email address.',
        AuthFailure.userNotFound => 'No account was found for that email.',
        AuthFailure.networkUnavailable =>
          'No connection. You can still use the app offline.',
        AuthFailure.tooManyAttempts =>
          'Too many attempts. Please wait a few minutes and try again.',
        AuthFailure.unknown => 'Something went wrong. Please try again.',
      };
}

/// Thrown by the auth service when an attempt fails.
class AuthException implements Exception {
  const AuthException(this.failure);

  final AuthFailure failure;

  String get message => failure.message;

  @override
  String toString() => 'AuthException(${failure.name})';
}

/// The signed-in account, as the rest of the app sees it.
///
/// Deliberately thin: an id, and enough to show on a screen. Anything else about
/// the user lives in [UserProfile] in the local database, where it is encrypted
/// and under the user's control.
class AuthAccount {
  const AuthAccount({
    required this.id,
    this.email,
    this.displayName,
  });

  final String id;
  final String? email;
  final String? displayName;
}

/// Minimum password length accepted at sign-up.
///
/// Eight rather than six: the local database key does not depend on this, so the
/// password only guards the account, but a short password on a health-related
/// account is not worth defending.
const int kMinPasswordLength = 8;

/// What the app needs from an authentication provider.
abstract interface class AuthService {
  /// The current account, and every later change. Emits null when signed out.
  ///
  /// A stream rather than a getter because the router redirects on it: a token
  /// that expires or an account deleted from another device has to take the user
  /// back to the sign-in screen without anything having to poll.
  Stream<AuthAccount?> authStateChanges();

  /// The account signed in right now, if any.
  AuthAccount? get currentAccount;

  Future<AuthAccount> signIn({required String email, required String password});

  Future<AuthAccount> register({
    required String email,
    required String password,
    String? displayName,
  });

  Future<void> signOut();

  /// Deletes the account at the provider.
  ///
  /// Only the provider's side. Wiping the local database and the encryption key is
  /// the repository's job, and both have to happen; the order matters, and
  /// `Repository.deleteEverything` owns it.
  Future<void> deleteAccount();
}

/// Validates an email address well enough to catch a typo.
///
/// Deliberately loose. Full RFC 5322 validation rejects addresses that work and
/// accepts ones that do not; the provider is the real authority, and this only
/// exists so the user gets an inline error instead of a round trip.
bool looksLikeEmail(String value) {
  final trimmed = value.trim();
  if (trimmed.length < 5 || trimmed.contains(' ')) return false;
  final at = trimmed.indexOf('@');
  if (at <= 0 || at != trimmed.lastIndexOf('@')) return false;
  final domain = trimmed.substring(at + 1);
  return domain.contains('.') &&
      !domain.startsWith('.') &&
      !domain.endsWith('.');
}

/// An on-device account store, used when no cloud provider is configured.
///
/// This is the default, and it is a real implementation rather than a stub: the
/// app is fully usable with it, which is what makes the cloud genuinely optional.
///
/// It is not a security boundary and does not pretend to be one. Anyone holding an
/// unlocked phone can sign in as its owner. That is the same guarantee the OS lock
/// screen gives, and the data itself is protected by SQLCipher either way. What
/// this does provide is separation: two people using a shared phone get separate
/// baselines, which is what the account is actually for.
class LocalAuthService implements AuthService {
  LocalAuthService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accountsKey = 'neurascan_local_accounts';
  static const _sessionKey = 'neurascan_local_session';

  final FlutterSecureStorage _storage;
  final _controller = StreamController<AuthAccount?>.broadcast();

  AuthAccount? _current;
  bool _restored = false;

  @override
  AuthAccount? get currentAccount => _current;

  @override
  Stream<AuthAccount?> authStateChanges() async* {
    await _restoreSession();
    yield _current;
    yield* _controller.stream;
  }

  /// Reloads the signed-in account after a restart.
  ///
  /// Without this the user would be sent back to sign-in every launch, which for a
  /// screening app used every two days would be most of the friction in the
  /// product.
  Future<void> _restoreSession() async {
    if (_restored) return;
    _restored = true;

    final raw = await _storage.read(key: _sessionKey);
    if (raw == null) return;

    final accounts = await _readAccounts();
    final record = accounts[raw];
    if (record != null) {
      _current = _toAccount(raw, record);
    }
  }

  @override
  Future<AuthAccount> signIn({
    required String email,
    required String password,
  }) async {
    final normalised = _normaliseEmail(email);
    if (!looksLikeEmail(normalised)) {
      throw const AuthException(AuthFailure.invalidEmail);
    }

    final accounts = await _readAccounts();
    final entry = accounts.entries
        .where((e) => e.value['email'] == normalised)
        .firstOrNull;
    if (entry == null) {
      throw const AuthException(AuthFailure.userNotFound);
    }
    if (entry.value['password'] != _hash(password, entry.value['salt']!)) {
      throw const AuthException(AuthFailure.invalidCredentials);
    }

    return _completeSignIn(entry.key, entry.value);
  }

  @override
  Future<AuthAccount> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final normalised = _normaliseEmail(email);
    if (!looksLikeEmail(normalised)) {
      throw const AuthException(AuthFailure.invalidEmail);
    }
    if (password.length < kMinPasswordLength) {
      throw const AuthException(AuthFailure.weakPassword);
    }

    final accounts = await _readAccounts();
    if (accounts.values.any((record) => record['email'] == normalised)) {
      throw const AuthException(AuthFailure.emailAlreadyInUse);
    }

    final id = _generateId();
    final salt = _generateId();
    final record = <String, String>{
      'email': normalised,
      'salt': salt,
      'password': _hash(password, salt),
      if (displayName != null && displayName.trim().isNotEmpty)
        'displayName': displayName.trim(),
    };

    accounts[id] = record;
    await _writeAccounts(accounts);
    return _completeSignIn(id, record);
  }

  @override
  Future<void> signOut() async {
    await _storage.delete(key: _sessionKey);
    _current = null;
    _controller.add(null);
  }

  @override
  Future<void> deleteAccount() async {
    final id = _current?.id;
    if (id == null) return;

    final accounts = await _readAccounts()
      ..remove(id);
    await _writeAccounts(accounts);
    await signOut();
  }

  /// Releases the auth-state stream.
  Future<void> dispose() => _controller.close();

  Future<AuthAccount> _completeSignIn(
    String id,
    Map<String, String> record,
  ) async {
    await _storage.write(key: _sessionKey, value: id);
    _restored = true;
    _current = _toAccount(id, record);
    _controller.add(_current);
    return _current!;
  }

  AuthAccount _toAccount(String id, Map<String, String> record) => AuthAccount(
        id: id,
        email: record['email'],
        displayName: record['displayName'],
      );

  Future<Map<String, Map<String, String>>> _readAccounts() async {
    final raw = await _storage.read(key: _accountsKey);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final entry in decoded.entries)
        entry.key: (entry.value as Map).cast<String, String>(),
    };
  }

  Future<void> _writeAccounts(Map<String, Map<String, String>> accounts) =>
      _storage.write(key: _accountsKey, value: jsonEncode(accounts));

  static String _normaliseEmail(String email) => email.trim().toLowerCase();

  /// Salted hash of a password.
  ///
  /// Not a password-hashing function in the proper sense -- there is no key
  /// stretching, so this would not survive an offline attack on the stored value.
  /// It is not asked to: the record lives in the platform keystore, which is the
  /// actual protection, and no password ever leaves the device. The salt and hash
  /// are here so that the plaintext is not sitting in storage, and so that two
  /// users who pick the same password do not have matching records.
  ///
  /// The cloud implementation has none of this; the provider handles it properly.
  static String _hash(String password, String salt) {
    // FNV-1a over the salted bytes, folded to 64 bits and hex encoded.
    var hash = BigInt.parse('14695981039346656037');
    const prime = 1099511628211;
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final byte in utf8.encode('$salt:$password')) {
      hash = (hash ^ BigInt.from(byte)) * BigInt.from(prime) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static String _generateId() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
