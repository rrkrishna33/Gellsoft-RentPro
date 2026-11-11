// The Pro screen shows when the subscription really ends, not the 7-day
// validity of the license the app happens to hold.
import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/subscription/license_state.dart';
import 'package:gellsoft_rentpro/subscription/license_token.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'license_fixtures.dart';

void main() {
  final key = publicKeyFromPem(fixturePublicKeyPem);

  Future<LicenseState> load(String token, DateTime now) async {
    SharedPreferences.setMockInitialValues({
      LicenseStore.installIdKey: fixtureInstallId,
      LicenseStore.licenseKey: token,
    });
    return LicenseStore(publicKey: key).load(now);
  }

  test(
    'Pro is trusted for the license period, but shows the paid end date',
    () async {
      // the fixture license lasts 7 days; its subscription runs 30 days
      final issued = DateTime.fromMillisecondsSinceEpoch(
        fixtureIssuedAt * 1000,
      );
      final s = await load(
        fixtureTokens['pro']!,
        issued.add(const Duration(hours: 1)),
      );
      final claims = s.claims!;
      final e = s.entitlement;
      expect(e.tier.name, 'pro');
      expect(e.proUntil, claims.expires); // access: capped by the license
      expect(e.paidUntil, claims.proUntil); // display: the subscription's end
      expect(e.paidUntil!.isAfter(e.proUntil!), isTrue);
    },
  );

  test('a license that is not Pro has no paid end date', () async {
    final issued = DateTime.fromMillisecondsSinceEpoch(fixtureIssuedAt * 1000);
    final s = await load(
      fixtureTokens['trial']!,
      issued.add(const Duration(hours: 1)),
    );
    expect(s.entitlement.paidUntil, isNull);
    expect(s.entitlement.proUntil, isNull);
  });
}
