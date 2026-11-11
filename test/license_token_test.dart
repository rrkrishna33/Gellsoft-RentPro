import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/subscription/license_config.dart';
import 'package:gellsoft_rentpro/subscription/license_token.dart';

import 'license_fixtures.dart';

void main() {
  final key = publicKeyFromPem(fixturePublicKeyPem);

  Future<LicenseClaims?> check(String name, {String? installId}) =>
      verifyLicense(
        fixtureTokens[name]!,
        installId: installId ?? fixtureInstallId,
        publicKey: key,
      );

  test('licenses made by the real server code are accepted', () async {
    final pro = await check('pro');
    expect(pro, isNotNull);
    expect(pro!.tier, 'pro');
    expect(pro.installId, fixtureInstallId);
    expect(pro.enforce, isTrue);
    expect(pro.reason, 'play_active');
    expect(
      pro.proUntil!.millisecondsSinceEpoch ~/ 1000,
      fixtureIssuedAt + 30 * 86400,
    );
    expect(pro.trialEnd, isNotNull);

    final trial = await check('trial');
    expect(trial!.tier, 'trial');
    expect(trial.proUntil, isNull);

    final free = await check('free');
    expect(free!.tier, 'free');
    expect(free.enforce, isFalse);
  });

  test('a license is fresh until it expires, then only history', () async {
    final c = (await check('pro'))!;
    final exp = DateTime.fromMillisecondsSinceEpoch(fixtureExpires * 1000);
    expect(c.isFresh(exp.subtract(const Duration(seconds: 1))), isTrue);
    expect(c.isFresh(exp), isFalse);
    expect(c.isFresh(exp.add(const Duration(days: 3))), isFalse);
  });

  test('forged or wrong licenses are all refused', () async {
    for (final bad in [
      'tampered', // genuine free license edited to say pro
      'algNone', // "no signature needed" trick
      'otherKey', // signed by someone else's key
      'wrongApp', // made for a different app
      'garbage',
    ]) {
      expect(await check(bad), isNull, reason: bad);
    }
  });

  test('a license for another install is refused', () async {
    expect(await check('wrongInstall'), isNull);
    // ...and a good license does not work for a different install id
    expect(
      await check('pro', installId: '99999999-2222-4333-8444-555555555555'),
      isNull,
    );
  });

  test('empty and odd input never throws', () async {
    for (final s in ['', '.', '..', 'a.b.c', 'a.b', ' ', '🙂.🙂.🙂']) {
      expect(
        await verifyLicense(s, installId: fixtureInstallId, publicKey: key),
        isNull,
        reason: s,
      );
    }
  });

  test('a good license is refused under a different public key', () async {
    final prod = publicKeyFromPem(licensePublicKeyPem);
    expect(
      await verifyLicense(
        fixtureTokens['pro']!,
        installId: fixtureInstallId,
        publicKey: prod,
      ),
      isNull,
    );
  });

  test('the key built into the app is a valid Ed25519 key', () {
    expect(publicKeyFromPem(licensePublicKeyPem), hasLength(32));
    expect(
      () => publicKeyFromPem(
        '-----BEGIN PUBLIC KEY-----\nAAAA\n-----END PUBLIC KEY-----',
      ),
      throwsFormatException,
    );
  });
}
