import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../subscription/account.dart';
import 'backup_service.dart';

/// The only Drive permission asked for: a hidden folder that only this app can
/// see. RentPro cannot read or change anything else in the person's Drive.
const driveAppDataScope = 'https://www.googleapis.com/auth/drive.appdata';

/// A backup file as Drive lists it.
class DriveFile {
  const DriveFile({
    required this.id,
    required this.name,
    required this.size,
    required this.modified,
  });
  final String id;
  final String name;
  final int size;
  final DateTime modified;
}

/// Drive refused the token (revoked, expired, or the permission was withdrawn).
class DriveAuthRejected implements Exception {
  const DriveAuthRejected();
}

/// Drive could not be reached, or answered with an error worth retrying.
class DriveUnavailable implements Exception {
  const DriveUnavailable([this.detail = '']);
  final String detail;
  @override
  String toString() => 'DriveUnavailable($detail)';
}

/// The person's Drive has no space left.
class DriveFull implements Exception {
  const DriveFull();
}

/// The few Drive calls a backup needs, all inside the app's hidden folder.
abstract class DriveApi {
  /// Newest first.
  Future<List<DriveFile>> list();
  Future<void> upload(String name, Uint8List bytes);
  Future<Uint8List> download(String id, {required int maxBytes});
  Future<void> delete(String id);

  /// Whose Drive this token opens, or null if Google does not say.
  Future<String?> accountEmail();
}

class HttpDriveApi implements DriveApi {
  HttpDriveApi(this._token, {this.baseUrl = 'https://www.googleapis.com'});
  final String _token;
  final String baseUrl;

  static const _timeout = Duration(seconds: 30);
  static const _uploadTimeout = Duration(minutes: 3);
  static const _maxJson = 256 * 1024;

  Future<({int status, Uint8List body, HttpHeaders headers})> _send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? body,
    Duration timeout = _timeout,
    int maxBytes = _maxJson,
  }) async {
    if (uri.scheme != 'https') throw const DriveUnavailable('https only');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.openUrl(method, uri);
      req.headers.set('Authorization', 'Bearer $_token');
      headers.forEach(req.headers.set);
      if (body != null) {
        req.headers.contentLength = body.length;
        req.add(body);
      }
      final res = await req.close().timeout(timeout);
      final out = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(timeout)) {
        out.add(chunk);
        if (out.length > maxBytes) throw const DriveUnavailable('too large');
      }
      final bytes = out.takeBytes();
      _check(res.statusCode, bytes);
      return (status: res.statusCode, body: bytes, headers: res.headers);
    } on DriveAuthRejected {
      rethrow;
    } on DriveUnavailable {
      rethrow;
    } on DriveFull {
      rethrow;
    } catch (e) {
      throw DriveUnavailable(e.runtimeType.toString());
    } finally {
      client.close(force: true);
    }
  }

  void _check(int status, Uint8List body) {
    if (status >= 200 && status < 300) return;
    if (status == 401) throw const DriveAuthRejected();
    if (status == 403) {
      final text = utf8.decode(body, allowMalformed: true);
      if (text.contains('storageQuotaExceeded')) throw const DriveFull();
      if (text.contains('rateLimitExceeded')) {
        throw const DriveUnavailable('rate limit');
      }
      throw const DriveAuthRejected();
    }
    throw DriveUnavailable('HTTP $status');
  }

  Object? _json(Uint8List body) {
    try {
      return jsonDecode(utf8.decode(body));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<DriveFile>> list() async {
    final r = await _send(
      'GET',
      Uri.parse('$baseUrl/drive/v3/files').replace(
        queryParameters: {
          'spaces': 'appDataFolder',
          'orderBy': 'modifiedTime desc',
          'pageSize': '100',
          'fields': 'files(id,name,size,modifiedTime)',
        },
      ),
    );
    final json = _json(r.body);
    if (json is! Map || json['files'] is! List) {
      throw const DriveUnavailable('bad list');
    }
    final out = <DriveFile>[];
    for (final f in json['files'] as List) {
      if (f is! Map) continue;
      final id = f['id'];
      final name = f['name'];
      final when = DateTime.tryParse('${f['modifiedTime']}');
      if (id is! String || name is! String || when == null) continue;
      out.add(
        DriveFile(
          id: id,
          name: name,
          size: int.tryParse('${f['size']}') ?? 0,
          modified: when.toLocal(),
        ),
      );
    }
    return out;
  }

  @override
  Future<void> upload(String name, Uint8List bytes) async {
    // Resumable upload: works for any size, in two steps.
    final start = await _send(
      'POST',
      Uri.parse(
        '$baseUrl/upload/drive/v3/files',
      ).replace(queryParameters: {'uploadType': 'resumable'}),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        'X-Upload-Content-Type': 'application/octet-stream',
        'X-Upload-Content-Length': '${bytes.length}',
      },
      body: utf8.encode(
        jsonEncode({
          'name': name,
          'parents': ['appDataFolder'],
        }),
      ),
    );
    final location = start.headers.value('location');
    if (location == null) throw const DriveUnavailable('no upload url');
    await _send(
      'PUT',
      Uri.parse(location),
      headers: {'Content-Type': 'application/octet-stream'},
      body: bytes,
      timeout: _uploadTimeout,
    );
  }

  @override
  Future<Uint8List> download(String id, {required int maxBytes}) async {
    final r = await _send(
      'GET',
      Uri.parse(
        '$baseUrl/drive/v3/files/${Uri.encodeComponent(id)}',
      ).replace(queryParameters: {'alt': 'media'}),
      timeout: _uploadTimeout,
      maxBytes: maxBytes,
    );
    return r.body;
  }

  @override
  Future<void> delete(String id) async {
    await _send(
      'DELETE',
      Uri.parse('$baseUrl/drive/v3/files/${Uri.encodeComponent(id)}'),
    );
  }

  @override
  Future<String?> accountEmail() async {
    try {
      final r = await _send(
        'GET',
        Uri.parse(
          '$baseUrl/drive/v3/about',
        ).replace(queryParameters: {'fields': 'user(emailAddress)'}),
      );
      final json = _json(r.body);
      final user = json is Map ? json['user'] : null;
      final email = user is Map ? user['emailAddress'] : null;
      return email is String ? email : null;
    } on DriveAuthRejected {
      return null; // this call is only a safety check
    }
  }
}

/// An access token for the app's hidden Drive folder, and whose it is (when
/// known: Google only says so during an interactive sign-in).
class DriveToken {
  const DriveToken(this.accessToken, {this.email});
  final String accessToken;
  final String? email;
}

abstract class DriveAuth {
  /// A token if the person has already allowed Drive backup. With
  /// [interactive] false this never shows anything: it returns null instead.
  /// With [interactive] true it may show Google's account and permission
  /// screens, so call it only from a tap. Returns null if the person backs out.
  Future<DriveToken?> token({required bool interactive});

  /// Drops a token Drive turned down, so the next one is fresh.
  Future<void> forget(String accessToken);
}

class GoogleDriveAuth implements DriveAuth {
  static const _scopes = [driveAppDataScope];

  @override
  Future<DriveToken?> token({required bool interactive}) async {
    try {
      await ensureGoogleReady();
      final google = GoogleSignIn.instance;
      if (!interactive) {
        final authz = await google.authorizationClient.authorizationForScopes(
          _scopes,
        );
        return authz == null ? null : DriveToken(authz.accessToken);
      }
      final account = await google.authenticate(scopeHint: _scopes);
      final client = account.authorizationClient;
      final authz =
          await client.authorizationForScopes(_scopes) ??
          await client.authorizeScopes(_scopes);
      return DriveToken(authz.accessToken, email: account.email);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw DriveUnavailable(e.code.name);
    } on StateError catch (e) {
      throw DriveUnavailable(e.message);
    }
  }

  @override
  Future<void> forget(String accessToken) async {
    try {
      await GoogleSignIn.instance.authorizationClient.clearAuthorizationToken(
        accessToken: accessToken,
      );
    } catch (_) {
      // nothing cached
    }
  }
}

/// The backup file as it sits in Drive: gzip, then AES-256-GCM.
///
/// The key comes from the person's Google account email, so a new phone that
/// signs in to the same account can open it without remembering anything. That
/// keeps the file unreadable to anyone who only sees the bytes, but it is not a
/// password: whoever has the account's Drive and knows the email can open it.
class BackupCrypto {
  static final _magic = ascii.encode('GBPB');
  static const _version = 1;
  static const _nonceLength = 12;
  static const _macLength = 16;
  static final _cipher = AesGcm.with256bits();
  static final _salt = utf8.encode('gellsoft-rentpro-drive-backup-v1');

  static Future<SecretKey> _key(String email) =>
      Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(utf8.encode(email.trim().toLowerCase())),
        nonce: _salt,
      );

  static List<int> get _header => [..._magic, _version];

  static Future<Uint8List> seal(List<int> plain, String email) async {
    final box = await _cipher.encrypt(
      plain,
      secretKey: await _key(email),
      aad: _header,
    );
    return Uint8List.fromList([..._header, ...box.concatenation()]);
  }

  /// Throws [FormatException] for a file that is not a backup, was changed, or
  /// belongs to another account.
  static Future<Uint8List> open(Uint8List data, String email) async {
    final headerLength = _header.length;
    if (data.length < headerLength + _nonceLength + _macLength) {
      throw const FormatException('Not a backup');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (data[i] != _magic[i]) throw const FormatException('Not a backup');
    }
    if (data[_magic.length] != _version) {
      throw const FormatException(
        'This backup is from a newer version of the app. Please update the app.',
      );
    }
    try {
      final box = SecretBox.fromConcatenation(
        data.sublist(headerLength),
        nonceLength: _nonceLength,
        macLength: _macLength,
      );
      final plain = await _cipher.decrypt(
        box,
        secretKey: await _key(email),
        aad: _header,
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const FormatException(
        'This backup could not be opened. It may belong to a different Google account.',
      );
    }
  }
}

enum CloudResult {
  done,

  /// Not signed in to RentPro with Google.
  notSignedIn,

  /// Drive backup is off, or the permission is gone: turn it on again.
  notConnected,

  /// The person closed a Google screen. Nothing changed.
  cancelled,

  /// Another Google account than the one signed in to RentPro was chosen.
  wrongAccount,
  offline,
  driveFull,
  failed,

  /// Drive holds no backup for this account.
  notFound,

  /// The file is damaged, from another account, or from a newer app.
  badBackup,
}

class CloudOutcome {
  const CloudOutcome(this.result, [this.message]);
  final CloudResult result;

  /// A plain-language reason, for [CloudResult.badBackup].
  final String? message;
  bool get ok => result == CloudResult.done;
}

class CloudStatus {
  const CloudStatus({required this.on, required this.auto, this.last});
  final bool on;
  final bool auto;
  final DateTime? last;
}

/// Backs the app's data up to the person's own Google Drive and restores it.
///
/// A one-way snapshot of one phone, not a live sync between phones. The server
/// never sees the data.
class CloudBackupService {
  CloudBackupService({
    DriveAuth? auth,
    DriveApi Function(String token)? apiFor,
    AccountStore? accounts,
    Future<Uint8List> Function()? makeBackup,
    Future<void> Function(Uint8List data)? applyBackup,
    DateTime Function()? clock,
  }) : _auth = auth ?? GoogleDriveAuth(),
       _apiFor = apiFor ?? HttpDriveApi.new,
       _accounts = accounts ?? AccountStore(),
       _makeBackup = makeBackup ?? BackupService.create,
       _applyBackup = applyBackup ?? BackupService.restore,
       _clock = clock ?? DateTime.now;

  final DriveAuth _auth;
  final DriveApi Function(String token) _apiFor;
  final AccountStore _accounts;
  final Future<Uint8List> Function() _makeBackup;
  final Future<void> Function(Uint8List data) _applyBackup;
  final DateTime Function() _clock;

  // Start with e_ so a restore keeps them: they describe this phone, not the data.
  static const onKey = 'e_cloud_on';
  static const autoKey = 'e_cloud_auto';
  static const lastKey = 'e_cloud_last';
  static const triedKey = 'e_cloud_tried';

  static const namePrefix = 'backup-';
  static const nameSuffix = '.gbk';

  /// The newest backups kept in Drive; older ones are removed.
  static const keepVersions = 5;
  static const autoEvery = Duration(hours: 24);
  static const retryEvery = Duration(hours: 1);

  /// A backup is the database as text, so allow the same ceiling as a file.
  static const _maxDownload = BackupService.maxBackupBytes;

  static bool isBackupName(String n) =>
      n.startsWith(namePrefix) && n.endsWith(nameSuffix);

  Future<CloudStatus> status() async {
    final sp = await SharedPreferences.getInstance();
    final ms = sp.getInt(lastKey);
    return CloudStatus(
      on: sp.getBool(onKey) ?? false,
      auto: sp.getBool(autoKey) ?? true,
      last: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  Future<void> setAuto(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(autoKey, value);
  }

  /// Asks the person to allow Drive backup. Call from a tap.
  Future<CloudOutcome> connect() async {
    final account = await _accounts.load();
    if (account == null) return const CloudOutcome(CloudResult.notSignedIn);
    try {
      final token = await _auth.token(interactive: true);
      if (token == null) return const CloudOutcome(CloudResult.cancelled);
      if (!_sameAccount(token.email, account.email)) {
        return const CloudOutcome(CloudResult.wrongAccount);
      }
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(onKey, true);
      return const CloudOutcome(CloudResult.done);
    } on DriveUnavailable {
      return const CloudOutcome(CloudResult.failed);
    }
  }

  /// Stops backing up. With [deleteBackups] the copies in Drive go too; if they
  /// cannot be removed right now, nothing is turned off.
  Future<CloudOutcome> disconnect({bool deleteBackups = false}) async {
    if (deleteBackups) {
      final r = await _run((api, account) async {
        for (final f in await api.list()) {
          if (isBackupName(f.name)) await api.delete(f.id);
        }
      });
      if (!r.ok) return r;
    }
    final sp = await SharedPreferences.getInstance();
    await sp.remove(onKey);
    await sp.remove(lastKey);
    await sp.remove(triedKey);
    return const CloudOutcome(CloudResult.done);
  }

  /// Uploads a fresh backup. [interactive] allows Google's permission screen
  /// when the earlier permission has lapsed (only from a tap).
  Future<CloudOutcome> backupNow({bool interactive = false}) async {
    final r = await _run((api, account) async {
      final plain = await _makeBackup();
      final sealed = await BackupCrypto.seal(gzip.encode(plain), account.email);
      final stamp = _clock().millisecondsSinceEpoch;
      await api.upload('$namePrefix$stamp$nameSuffix', sealed);
      try {
        final mine = (await api.list()).where((f) => isBackupName(f.name));
        for (final old in mine.skip(keepVersions)) {
          await api.delete(old.id);
        }
      } on DriveUnavailable {
        // tidying up can wait for the next backup
      }
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(lastKey, stamp);
    }, interactive: interactive);
    return r;
  }

  /// The once-a-day backup. Quiet: no screens, and a failure just waits an hour.
  Future<bool> autoBackupIfDue() async {
    final sp = await SharedPreferences.getInstance();
    if (!(sp.getBool(onKey) ?? false) || !(sp.getBool(autoKey) ?? true)) {
      return false;
    }
    final now = _clock().millisecondsSinceEpoch;
    final last = sp.getInt(lastKey) ?? 0;
    final tried = sp.getInt(triedKey) ?? 0;
    if (now - last < autoEvery.inMilliseconds) return false;
    if (now - tried < retryEvery.inMilliseconds) return false;
    await sp.setInt(triedKey, now);
    return (await backupNow()).ok;
  }

  /// The backups in Drive, newest first.
  Future<({CloudOutcome outcome, List<DriveFile> files})> versions({
    bool interactive = false,
  }) async {
    var files = <DriveFile>[];
    final outcome = await _run((api, account) async {
      files = (await api.list()).where((f) => isBackupName(f.name)).toList();
    }, interactive: interactive);
    if (outcome.ok && files.isEmpty) {
      return (outcome: const CloudOutcome(CloudResult.notFound), files: files);
    }
    return (outcome: outcome, files: files);
  }

  /// Replaces ALL data on this phone with [file]. The caller restarts the app.
  Future<CloudOutcome> restore(DriveFile file, {bool interactive = false}) {
    return _run((api, account) async {
      final data = await api.download(file.id, maxBytes: _maxDownload);
      final Uint8List plain;
      try {
        plain = Uint8List.fromList(
          gzip.decode(await BackupCrypto.open(data, account.email)),
        );
      } on FormatException {
        rethrow;
      } catch (_) {
        throw const FormatException('This backup could not be read.');
      }
      await _applyBackup(plain);
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(onKey, true);
    }, interactive: interactive);
  }

  bool _sameAccount(String? driveEmail, String signedIn) =>
      driveEmail == null ||
      driveEmail.trim().toLowerCase() == signedIn.trim().toLowerCase();

  /// Gets a token for the signed-in account, runs [body], and turns every
  /// failure into a [CloudResult].
  Future<CloudOutcome> _run(
    Future<void> Function(DriveApi api, Account account) body, {
    bool interactive = false,
  }) async {
    final account = await _accounts.load();
    if (account == null) return const CloudOutcome(CloudResult.notSignedIn);
    String? used;
    try {
      var token = await _auth.token(interactive: false);
      if (token == null && interactive) {
        token = await _auth.token(interactive: true);
        if (token == null) return const CloudOutcome(CloudResult.cancelled);
      }
      if (token == null) return const CloudOutcome(CloudResult.notConnected);
      used = token.accessToken;
      final api = _apiFor(token.accessToken);
      final who = token.email ?? await api.accountEmail();
      if (!_sameAccount(who, account.email)) {
        return const CloudOutcome(CloudResult.wrongAccount);
      }
      await body(api, account);
      return const CloudOutcome(CloudResult.done);
    } on DriveAuthRejected {
      if (used != null) await _auth.forget(used);
      return const CloudOutcome(CloudResult.notConnected);
    } on DriveFull {
      return const CloudOutcome(CloudResult.driveFull);
    } on DriveUnavailable {
      return const CloudOutcome(CloudResult.offline);
    } on FormatException catch (e) {
      return CloudOutcome(CloudResult.badBackup, e.message);
    } catch (_) {
      return const CloudOutcome(CloudResult.failed);
    }
  }
}

final cloudBackupProvider = Provider((_) => CloudBackupService());
