import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'license_config.dart';

/// The server could not give an answer right now (offline, busy, or Google
/// was unreachable). The app keeps the license it already has.
class LicenseUnavailable implements Exception {
  const LicenseUnavailable([this.detail = '']);
  final String detail;
  @override
  String toString() => 'LicenseUnavailable($detail)';
}

/// Talks to the license server. Sends only a random install id, a one-way
/// scrambled id of the phone, the app version and (after a purchase) Google's
/// purchase token: no shop data.
abstract class LicenseApi {
  /// Returns the signed license text. Throws [LicenseUnavailable].
  Future<String> refresh({
    required String installId,
    required String appVersion,
    String? purchaseToken,
    String? deviceId,
  });
}

class HttpLicenseApi implements LicenseApi {
  HttpLicenseApi({this.baseUrl = licenseServerUrl});
  final String baseUrl;

  static const _timeout = Duration(seconds: 15);
  static const _maxBody = 64 * 1024;

  @override
  Future<String> refresh({
    required String installId,
    required String appVersion,
    String? purchaseToken,
    String? deviceId,
  }) async {
    if (!baseUrl.startsWith('https://')) {
      throw const LicenseUnavailable('license server must use https');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(
        Uri.parse('$baseUrl/v1/license/refresh'),
      );
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode({
          'install_id': installId,
          'app_version': appVersion,
          if (purchaseToken != null) 'purchase_token': purchaseToken,
          if (deviceId != null) 'device_id': deviceId,
        }),
      );
      final res = await req.close().timeout(_timeout);
      final body = await res.transform(utf8.decoder).join().timeout(_timeout);
      if (res.statusCode != 200 || body.length > _maxBody) {
        throw LicenseUnavailable('HTTP ${res.statusCode}');
      }
      final json = jsonDecode(body);
      final license = json is Map ? json['license'] : null;
      if (license is! String || license.isEmpty) {
        throw const LicenseUnavailable('no license in reply');
      }
      return license;
    } on LicenseUnavailable {
      rethrow;
    } catch (e) {
      // SocketException, TimeoutException, TLS or JSON errors: all just "not now".
      throw LicenseUnavailable(e.runtimeType.toString());
    } finally {
      client.close(force: true);
    }
  }
}
