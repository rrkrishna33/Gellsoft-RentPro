import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'license_client.dart';
import 'license_config.dart';
import 'license_state.dart';
import 'license_sync.dart';

/// Who is signed in with Google. Optional: billing never needs it. It lets the
/// license server tie the trial (and later backup) to a person, not just a phone.
class Account {
  const Account({required this.email, this.name = ''});
  final String email;
  final String name;
}

/// The server did not accept the Google sign-in (an expired or foreign token).
class AccountRejected implements Exception {
  const AccountRejected();
}

/// Google sign-in is not possible right now (misconfigured, no Play services).
class GoogleUnavailable implements Exception {
  const GoogleUnavailable([this.detail = '']);
  final String detail;
  @override
  String toString() => 'GoogleUnavailable($detail)';
}

/// The Google sign-in itself: the phone's account chooser. Returns the ID token
/// that proves who signed in, or null if the person backed out.
abstract class GoogleLogin {
  Future<String?> idToken();
  Future<void> signOut();
}

bool _googleReady = false;

/// Sets Google sign-in up once per run. Sign-in and Drive backup share it.
Future<void> ensureGoogleReady() async {
  if (_googleReady) return;
  await GoogleSignIn.instance.initialize(serverClientId: googleWebClientId);
  _googleReady = true;
}

class PlatformGoogleLogin implements GoogleLogin {
  @override
  Future<String?> idToken() async {
    final google = GoogleSignIn.instance;
    try {
      await ensureGoogleReady();
      final account = await google.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw GoogleUnavailable(e.code.name);
    } on StateError catch (e) {
      throw GoogleUnavailable(e.message);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      if (_googleReady) await GoogleSignIn.instance.signOut();
    } catch (_) {
      // nothing to sign out of
    }
  }
}

/// The two account calls to the license server.
abstract class AccountApi {
  /// Throws [AccountRejected] or [LicenseUnavailable].
  Future<Account> signIn({required String installId, required String idToken});

  /// Best effort; throws [LicenseUnavailable] when the server cannot be reached.
  Future<void> signOut({required String installId});

  /// Erases the account from the server. [idToken] is a fresh Google token, so
  /// only the account's owner can do it. Throws [AccountRejected] or
  /// [LicenseUnavailable].
  Future<void> delete({required String idToken});
}

class HttpAccountApi implements AccountApi {
  HttpAccountApi({this.baseUrl = licenseServerUrl});
  final String baseUrl;

  static const _timeout = Duration(seconds: 15);
  static const _maxBody = 16 * 1024;

  Future<(int, Object?)> _post(String path, Map<String, Object?> body) async {
    if (!baseUrl.startsWith('https://')) {
      throw const LicenseUnavailable('license server must use https');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(Uri.parse('$baseUrl$path'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final res = await req.close().timeout(_timeout);
      final text = await res.transform(utf8.decoder).join().timeout(_timeout);
      if (text.length > _maxBody) throw const LicenseUnavailable('too large');
      Object? json;
      try {
        json = jsonDecode(text);
      } catch (_) {
        json = null;
      }
      return (res.statusCode, json);
    } on LicenseUnavailable {
      rethrow;
    } catch (e) {
      throw LicenseUnavailable(e.runtimeType.toString());
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<Account> signIn({
    required String installId,
    required String idToken,
  }) async {
    final (code, json) = await _post('/v1/account/signin', {
      'install_id': installId,
      'id_token': idToken,
    });
    if (code == 401) throw const AccountRejected();
    if (code != 200 || json is! Map || json['email'] is! String) {
      throw LicenseUnavailable('HTTP $code');
    }
    return Account(
      email: json['email'] as String,
      name: json['name'] is String ? json['name'] as String : '',
    );
  }

  @override
  Future<void> signOut({required String installId}) async {
    final (code, _) = await _post('/v1/account/signout', {
      'install_id': installId,
    });
    if (code != 200) throw LicenseUnavailable('HTTP $code');
  }

  @override
  Future<void> delete({required String idToken}) async {
    final (code, _) = await _post('/v1/account/delete', {'id_token': idToken});
    if (code == 401) throw const AccountRejected();
    if (code != 200) throw LicenseUnavailable('HTTP $code');
  }
}

/// Remembers who is signed in, on this phone only.
class AccountStore {
  static const emailKey = 'acct_email';
  static const nameKey = 'acct_name';

  Future<Account?> load() async {
    final sp = await SharedPreferences.getInstance();
    final email = sp.getString(emailKey);
    if (email == null || email.isEmpty) return null;
    return Account(email: email, name: sp.getString(nameKey) ?? '');
  }

  Future<void> save(Account a) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(emailKey, a.email);
    await sp.setString(nameKey, a.name);
  }

  Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(emailKey);
    await sp.remove(nameKey);
  }
}

enum DeleteResult {
  /// The account is gone from the server and from this phone.
  deleted,

  /// The person closed the Google chooser. Nothing was changed.
  cancelled,

  /// The server could not be reached. Nothing was changed: try again.
  offline,

  /// Google or the server refused it (for example a different account was picked).
  failed,
}

enum SignInResult {
  /// Signed in, and the license was refreshed.
  signedIn,

  /// The person closed the Google chooser.
  cancelled,

  /// The license server could not be reached. Nothing was changed.
  offline,

  /// Google or the server refused it.
  failed,
}

class AccountService {
  AccountService({
    GoogleLogin? google,
    AccountApi? api,
    AccountStore? accounts,
    LicenseStore? licenses,
    LicenseSync? sync,
  }) : _google = google ?? PlatformGoogleLogin(),
       _api = api ?? HttpAccountApi(),
       _accounts = accounts ?? AccountStore(),
       _licenses = licenses ?? LicenseStore(),
       _sync = sync ?? LicenseSync();

  final GoogleLogin _google;
  final AccountApi _api;
  final AccountStore _accounts;
  final LicenseStore _licenses;
  final LicenseSync _sync;

  Future<Account?> current() => _accounts.load();

  Future<({SignInResult result, Account? account})> signIn() async {
    final String? token;
    try {
      token = await _google.idToken();
    } on GoogleUnavailable {
      return (result: SignInResult.failed, account: null);
    }
    if (token == null) return (result: SignInResult.cancelled, account: null);

    // the server only knows installs that have asked for a license once
    await _sync.refresh();
    final Account account;
    try {
      account = await _api.signIn(
        installId: await _licenses.installId(),
        idToken: token,
      );
    } on AccountRejected {
      return (result: SignInResult.failed, account: null);
    } on LicenseUnavailable {
      return (result: SignInResult.offline, account: null);
    }
    await _accounts.save(account);
    // the trial may now start earlier: it follows the account
    await _sync.refresh();
    return (result: SignInResult.signedIn, account: account);
  }

  /// Deletes the account on the server, then signs out here. Google is asked
  /// once more who the person is, so nobody can delete someone else's account.
  /// Bills and other business data on the phone are never touched.
  Future<DeleteResult> deleteAccount() async {
    final String? token;
    try {
      token = await _google.idToken();
    } on GoogleUnavailable {
      return DeleteResult.failed;
    }
    if (token == null) return DeleteResult.cancelled;
    try {
      await _api.delete(idToken: token);
    } on AccountRejected {
      return DeleteResult.failed;
    } on LicenseUnavailable {
      return DeleteResult.offline;
    }
    await _google.signOut();
    await _accounts.clear();
    return DeleteResult.deleted;
  }

  /// Signs out on this phone, and tells the server if it can be reached.
  Future<void> signOut() async {
    await _google.signOut();
    try {
      await _api.signOut(installId: await _licenses.installId());
    } on LicenseUnavailable {
      // still signed out here; the server link is harmless
    }
    await _accounts.clear();
  }
}

final accountServiceProvider = Provider((_) => AccountService());

class AccountNotifier extends AsyncNotifier<Account?> {
  @override
  Future<Account?> build() => ref.read(accountServiceProvider).current();

  Future<SignInResult> signIn() async {
    final r = await ref.read(accountServiceProvider).signIn();
    if (r.result == SignInResult.signedIn) {
      state = AsyncData(r.account);
      ref.invalidate(licenseProvider);
    }
    return r.result;
  }

  Future<void> signOut() async {
    await ref.read(accountServiceProvider).signOut();
    state = const AsyncData(null);
  }

  Future<DeleteResult> deleteAccount() async {
    final r = await ref.read(accountServiceProvider).deleteAccount();
    if (r == DeleteResult.deleted) state = const AsyncData(null);
    return r;
  }
}

final accountProvider = AsyncNotifierProvider<AccountNotifier, Account?>(
  AccountNotifier.new,
);
