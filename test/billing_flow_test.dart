import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/theme.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:gellsoft_rentpro/subscription/billing.dart';
import 'package:gellsoft_rentpro/subscription/license_client.dart';
import 'package:gellsoft_rentpro/subscription/license_state.dart';
import 'package:gellsoft_rentpro/subscription/license_sync.dart';
import 'package:gellsoft_rentpro/subscription/license_token.dart';
import 'package:gellsoft_rentpro/subscription/plan.dart';
import 'package:gellsoft_rentpro/subscription/pro_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_billing.dart';
import 'fake_device.dart';
import 'license_fixtures.dart';

/// Pretend license server: answers with the next prepared reply.
class FakeApi implements LicenseApi {
  final replies = <Object>[]; // a license string, or an exception
  final calls =
      <
        ({String installId, String appVersion, String? token, String? deviceId})
      >[];

  @override
  Future<String> refresh({
    required String installId,
    required String appVersion,
    String? purchaseToken,
    String? deviceId,
  }) async {
    calls.add((
      installId: installId,
      appVersion: appVersion,
      token: purchaseToken,
      deviceId: deviceId,
    ));
    final r = replies.isEmpty
        ? const LicenseUnavailable('none')
        : replies.removeAt(0);
    if (r is String) return r;
    throw r;
  }
}

final key = publicKeyFromPem(fixturePublicKeyPem);
final issued = DateTime.fromMillisecondsSinceEpoch(fixtureIssuedAt * 1000);
final expires = DateTime.fromMillisecondsSinceEpoch(fixtureExpires * 1000);
DateTime clockAt = issued.add(const Duration(hours: 1));

String lic(String name) => fixtureTokens[name]!;

({LicenseSync sync, LicenseStore store, FakeApi api}) setup() {
  final api = FakeApi();
  final store = LicenseStore(publicKey: key);
  final sync = LicenseSync(
    api: api,
    store: store,
    publicKey: key,
    appVersion: '9.9.9',
    clock: () => clockAt,
    device: FakeDevice(),
  );
  return (sync: sync, store: store, api: api);
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      LicenseStore.installIdKey: fixtureInstallId,
    });
    clockAt = issued.add(const Duration(hours: 1));
    BillingController.restoreWait = Duration.zero;
  });
  tearDown(() => Lang.current = AppLanguage.en);

  group('license sync', () {
    test('a Pro license from the server unlocks Pro on the phone', () async {
      final s = setup();
      s.api.replies.add(lic('pro'));
      final r = await s.sync.refresh();
      expect(r.result, SyncResult.updated);

      final st = await s.store.load(clockAt);
      expect(st.entitlement.tier, Tier.pro);
      expect(st.entitlement.enforced, isTrue);
      expect(st.claims!.tier, 'pro');
      expect(st.entitlement.allows(ProFeature.unlimitedBookings), isTrue);
    });

    test(
      'what is sent: install id and app version, and nothing else',
      () async {
        final s = setup();
        s.api.replies.add(lic('trial'));
        await s.sync.refresh();
        expect(s.api.calls.single.installId, fixtureInstallId);
        expect(s.api.calls.single.appVersion, '9.9.9');
        expect(s.api.calls.single.token, isNull);
      },
    );

    test(
      'Pro lasts until the license runs out, then needs the server',
      () async {
        final s = setup();
        s.api.replies.add(lic('pro'));
        await s.sync.refresh();
        // a day before the license expires
        var st = await s.store.load(expires.subtract(const Duration(days: 1)));
        expect(st.entitlement.tier, Tier.pro);
        // well after it expired (and after the trial) : back to Free, data kept
        st = await s.store.load(expires.add(const Duration(days: 20)));
        expect(st.entitlement.tier, Tier.free);
        expect(st.entitlement.enforced, isTrue);
      },
    );

    test('the server decides the trial end', () async {
      final s = setup();
      s.api.replies.add(lic('trial'));
      await s.sync.refresh();
      final st = await s.store.load(clockAt);
      expect(st.entitlement.tier, Tier.trial);
      expect(
        st.entitlement.trialEnds,
        issued.add(const Duration(days: trialLengthDays)),
      );
    });

    test('the server can leave the paywall off', () async {
      final s = setup();
      s.api.replies.add(lic('free'));
      await s.sync.refresh();
      final st = await s.store.load(clockAt);
      expect(st.entitlement.enforced, isFalse);
      expect(st.entitlement.unlocked, isTrue);
    });

    test('offline or server busy: the old license is kept', () async {
      final s = setup();
      s.api.replies
        ..add(lic('pro'))
        ..add(const LicenseUnavailable('HTTP 503'));
      await s.sync.refresh();
      final r = await s.sync.refresh();
      expect(r.result, SyncResult.unavailable);
      expect((await s.store.load(clockAt)).entitlement.tier, Tier.pro);
    });

    test('a reinstall looks for an earlier purchase, once', () async {
      final s = setup();
      s.api.replies.add(lic('trial'));
      await s.sync.refresh();
      expect(await s.sync.shouldAutoRestore(), isTrue);
      await s.sync.markAutoRestored();
      expect(await s.sync.shouldAutoRestore(), isFalse);
    });

    test(
      'no automatic restore without a license, or with Pro already',
      () async {
        var s = setup();
        expect(await s.sync.shouldAutoRestore(), isFalse); // never online yet

        s.api.replies.add(lic('pro'));
        await s.sync.refresh();
        expect(await s.sync.shouldAutoRestore(), isFalse);
      },
    );

    test('no automatic restore while the paywall is off', () async {
      final s = setup();
      s.api.replies.add(lic('free'));
      await s.sync.refresh();
      expect(await s.sync.shouldAutoRestore(), isFalse);
    });

    test(
      'no automatic restore when a purchase token is already kept',
      () async {
        final s = setup();
        s.api.replies.add(lic('pro'));
        await s.sync.refresh(purchaseToken: 'kept');
        s.api.replies.add(lic('trial'));
        await s.sync.refresh();
        expect(await s.sync.shouldAutoRestore(), isFalse);
      },
    );

    test('forged, foreign or other-install licenses are ignored', () async {
      for (final bad in [
        'tampered',
        'algNone',
        'otherKey',
        'wrongApp',
        'wrongInstall',
        'garbage',
      ]) {
        SharedPreferences.setMockInitialValues({
          LicenseStore.installIdKey: fixtureInstallId,
        });
        final s = setup();
        s.api.replies.add(lic(bad));
        final r = await s.sync.refresh();
        expect(r.result, SyncResult.invalid, reason: bad);
        expect((await s.store.load(clockAt)).claims, isNull, reason: bad);
        expect(
          (await s.store.load(clockAt)).entitlement.tier,
          isNot(Tier.pro),
          reason: bad,
        );
      }
    });

    test('a bad reply does not replace a good license', () async {
      final s = setup();
      s.api.replies
        ..add(lic('pro'))
        ..add(lic('tampered'));
      await s.sync.refresh();
      await s.sync.refresh();
      expect((await s.store.load(clockAt)).entitlement.tier, Tier.pro);
    });

    test('a forged license planted on the phone is not trusted', () async {
      SharedPreferences.setMockInitialValues({
        LicenseStore.installIdKey: fixtureInstallId,
        LicenseStore.licenseKey: lic('tampered'),
      });
      final st = await LicenseStore(publicKey: key).load(clockAt);
      expect(st.claims, isNull);
      expect(st.entitlement.tier, isNot(Tier.pro));
    });

    test(
      'the purchase token is kept only when it gave Pro, then re-sent',
      () async {
        var s = setup();
        s.api.replies.add(lic('free'));
        await s.sync.refresh(purchaseToken: 'tok-1');
        expect(await s.store.purchaseToken(), isNull);

        s = setup();
        s.api.replies
          ..add(lic('pro'))
          ..add(lic('pro'));
        await s.sync.refresh(purchaseToken: 'tok-2');
        expect(await s.store.purchaseToken(), 'tok-2');
        await s.sync.refresh(); // a later renewal check
        expect(s.api.calls.last.token, 'tok-2');
      },
    );

    test('renew when missing or older than 15 minutes', () async {
      final s = setup();
      expect(await s.sync.isStale(), isTrue); // none yet
      s.api.replies.add(lic('trial'));
      await s.sync.refresh();
      expect(
        await s.sync.isStale(issued.add(const Duration(minutes: 14))),
        isFalse,
      );
      expect(
        await s.sync.isStale(issued.add(const Duration(minutes: 16))),
        isTrue,
      );
    });
  });

  group('purchases', () {
    ({ProviderContainer c, FakeBilling gw, FakeApi api, LicenseStore store})
    boot({bool listen = true}) {
      final s = setup();
      final gw = FakeBilling(plans: [monthlyPlan, yearlyPlan]);
      final c = ProviderContainer(
        overrides: [
          billingGatewayProvider.overrideWithValue(gw),
          licenseSyncProvider.overrideWithValue(s.sync),
          // keeps the real license provider (and the real clock) out of it
          licenseProvider.overrideWith(
            () => _Fixed(const Entitlement(tier: Tier.free, enforced: true)),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.listen(billingProvider, (_, _) {});
      return (c: c, gw: gw, api: s.api, store: s.store);
    }

    PurchaseUpdate bought({
      String id = 'gellsoft_pro',
      String? token = 'tok',
    }) => PurchaseUpdate(
      stage: PurchaseStage.purchased,
      productId: id,
      token: token,
    );

    test('plans load; no Play Store means no plans', () async {
      var b = boot();
      await b.c.read(billingProvider.notifier).loadPlans();
      expect(b.c.read(billingProvider).plans!.map((p) => p.id), [
        'monthly',
        'yearly',
      ]);
      b = boot();
      b.gw.unavailable = true;
      await b.c.read(billingProvider.notifier).loadPlans();
      expect(b.c.read(billingProvider).plans, isNull);
      expect(b.c.read(billingProvider).loading, isFalse);
    });

    test('Subscribe starts the Google purchase', () async {
      final b = boot();
      await b.c.read(billingProvider.notifier).buy(monthlyPlan);
      expect(b.gw.bought, ['monthly']);
      b.gw.buyError = StateError('x');
      await b.c.read(billingProvider.notifier).buy(yearlyPlan);
      expect(b.c.read(billingProvider).note, BillingNote.failed);
      expect(b.c.read(billingProvider).busy, isFalse);
    });

    test(
      'a paid purchase: server checks it, Google is told, Pro is on',
      () async {
        final b = boot();
        b.api.replies.add(lic('pro'));
        b.gw.emit([bought(token: 'real-token')]);
        await settle();

        expect(b.api.calls.single.token, 'real-token');
        expect(b.gw.acknowledged, hasLength(1));
        expect(b.c.read(billingProvider).note, BillingNote.activated);
        expect(b.c.read(billingProvider).busy, isFalse);
        expect((await b.store.load(clockAt)).entitlement.tier, Tier.pro);
      },
    );

    test(
      'server unreachable: NOT acknowledged, so Google delivers it again',
      () async {
        final b = boot();
        b.api.replies.add(const LicenseUnavailable('offline'));
        b.gw.emit([bought()]);
        await settle();
        expect(b.gw.acknowledged, isEmpty);
        expect(b.c.read(billingProvider).note, BillingNote.offline);

        // next start: Google delivers it again and it goes through
        b.api.replies.add(lic('pro'));
        b.gw.emit([bought()]);
        await settle();
        expect(b.gw.acknowledged, hasLength(1));
        expect(b.c.read(billingProvider).note, BillingNote.activated);
      },
    );

    test(
      'server says not Pro (e.g. too many phones): told, but acknowledged',
      () async {
        final b = boot();
        b.api.replies.add(lic('free'));
        b.gw.emit([bought()]);
        await settle();
        expect(b.c.read(billingProvider).note, BillingNote.notActivated);
        expect(b.gw.acknowledged, hasLength(1));
        expect((await b.store.load(clockAt)).entitlement.tier, isNot(Tier.pro));
      },
    );

    test('a forged server reply is not acknowledged or applied', () async {
      final b = boot();
      b.api.replies.add(lic('tampered'));
      b.gw.emit([bought()]);
      await settle();
      expect(b.gw.acknowledged, isEmpty);
      expect(b.c.read(billingProvider).note, BillingNote.notActivated);
    });

    test(
      'pending, cancelled and failed purchases show the right note',
      () async {
        final b = boot();
        for (final (stage, note) in [
          (PurchaseStage.pending, BillingNote.pending),
          (PurchaseStage.cancelled, BillingNote.cancelled),
          (PurchaseStage.failed, BillingNote.failed),
        ]) {
          b.gw.emit([PurchaseUpdate(stage: stage, productId: 'gellsoft_pro')]);
          await settle();
          expect(b.c.read(billingProvider).note, note);
        }
        expect(b.api.calls, isEmpty);
      },
    );

    test(
      'other products and token-less purchases are ignored or failed',
      () async {
        final b = boot();
        b.gw.emit([bought(id: 'something_else')]);
        await settle();
        expect(b.api.calls, isEmpty);
        expect(b.c.read(billingProvider).note, BillingNote.none);

        b.gw.emit([bought(token: '')]);
        await settle();
        expect(b.api.calls, isEmpty);
        expect(b.c.read(billingProvider).note, BillingNote.failed);
      },
    );

    test('Restore purchases brings Pro back on a new phone', () async {
      final b = boot();
      b.gw.restoreResult = [bought(token: 'old-token')];
      b.api.replies.add(lic('pro'));
      await b.c.read(billingProvider.notifier).restore();
      expect(b.gw.restoreCalls, 1);
      expect(b.api.calls.single.token, 'old-token');
      expect(b.c.read(billingProvider).note, BillingNote.activated);
    });

    test('the automatic restore brings Pro back without any message', () async {
      final b = boot();
      b.gw.restoreResult = [bought(token: 'old-token')];
      b.api.replies.add(lic('pro'));
      final asked = await b.c.read(billingProvider.notifier).restoreQuietly();
      await settle();
      expect(asked, isTrue);
      expect(b.api.calls.single.token, 'old-token');
      expect(b.gw.acknowledged, hasLength(1));
      expect((await b.store.load(clockAt)).entitlement.tier, Tier.pro);
      expect(b.c.read(billingProvider).note, BillingNote.none);
      expect(b.c.read(billingProvider).busy, isFalse);
    });

    test(
      'the automatic restore with nothing to restore stays silent',
      () async {
        final b = boot();
        final asked = await b.c.read(billingProvider.notifier).restoreQuietly();
        expect(asked, isTrue);
        expect(b.api.calls, isEmpty);
        expect(b.c.read(billingProvider).note, BillingNote.none);
      },
    );

    test(
      'if Google cannot be asked, the automatic restore can retry',
      () async {
        final b = boot();
        b.gw.restoreError = StateError('no Play');
        final asked = await b.c.read(billingProvider.notifier).restoreQuietly();
        expect(asked, isFalse);
        expect(b.c.read(billingProvider).note, BillingNote.none);
      },
    );

    test('Restore with nothing to restore says so', () async {
      final b = boot();
      await b.c.read(billingProvider.notifier).restore();
      expect(b.c.read(billingProvider).note, BillingNote.restoredNothing);
      expect(b.c.read(billingProvider).busy, isFalse);
    });
  });

  group('purchase screen', () {
    Widget host(
      FakeBilling gw,
      Entitlement e, {
      AppLanguage lang = AppLanguage.en,
      double scale = 1,
    }) {
      Lang.current = lang;
      final s = setup();
      return ProviderScope(
        overrides: [
          billingGatewayProvider.overrideWithValue(gw),
          licenseSyncProvider.overrideWithValue(s.sync),
          licenseProvider.overrideWith(() => _Fixed(e)),
          bookingQuotaRepoProvider.overrideWithValue(_NoBookings()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: Locale(lang.code),
          supportedLocales: const [Locale('en'), Locale('ta')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const UpgradeScreen(),
        ),
      );
    }

    void phone(WidgetTester t) {
      t.view.physicalSize = const Size(360 * 3, 640 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
    }

    const free = Entitlement(tier: Tier.free, enforced: true);

    /// The list builds lazily, and a built row can still be below the screen.
    Future<void> scrollTo(WidgetTester t, Finder f) async {
      await t.scrollUntilVisible(
        f,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(f);
      await t.pumpAndSettle();
    }

    testWidgets('an old "Pro is now active" message is not shown again later', (
      t,
    ) async {
      phone(t);
      final s = setup();
      s.api.replies.add(lic('pro'));
      final gw = FakeBilling(plans: [monthlyPlan, yearlyPlan]);
      final c = ProviderContainer(
        overrides: [
          billingGatewayProvider.overrideWithValue(gw),
          licenseSyncProvider.overrideWithValue(s.sync),
          licenseProvider.overrideWith(() => _Fixed(free)),
          bookingQuotaRepoProvider.overrideWithValue(_NoBookings()),
        ],
      );
      addTearDown(c.dispose);
      c.listen(billingProvider, (_, _) {});
      gw.emit([
        const PurchaseUpdate(
          stage: PurchaseStage.purchased,
          productId: 'gellsoft_pro',
          token: 'tok',
        ),
      ]);
      // wait until the purchase has been confirmed with the server
      for (var i = 0; i < 100; i++) {
        if (c.read(billingProvider).note == BillingNote.activated) break;
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(c.read(billingProvider).note, BillingNote.activated);

      // the Pro screen is opened later: the old message is gone
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const UpgradeScreen(),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Thank you! Pro is now active.'), findsNothing);
      expect(c.read(billingProvider).note, BillingNote.none);
    });

    testWidgets('Subscribe on a plan starts that purchase', (t) async {
      phone(t);
      final gw = FakeBilling(plans: [monthlyPlan, yearlyPlan]);
      await t.pumpWidget(host(gw, free));
      await t.pumpAndSettle();
      await scrollTo(t, find.text('Restore purchases'));
      await t.tap(find.text('Subscribe').last);
      await t.pumpAndSettle();
      expect(gw.bought, ['yearly']);
    });

    testWidgets('Restore purchases button asks Google', (t) async {
      phone(t);
      final gw = FakeBilling(plans: [monthlyPlan]);
      await t.pumpWidget(host(gw, free));
      await t.pumpAndSettle();
      await scrollTo(t, find.text('Restore purchases'));
      await t.tap(find.text('Restore purchases'));
      await t.pumpAndSettle();
      expect(gw.restoreCalls, 1);
      expect(
        find.text('No earlier purchase was found for this Google account.'),
        findsOneWidget,
      );
    });

    testWidgets('no Play Store: a clear message, no Subscribe button', (
      t,
    ) async {
      phone(t);
      await t.pumpWidget(host(FakeBilling(unavailable: true), free));
      await t.pumpAndSettle();
      await scrollTo(t, find.textContaining('Plans are not available'));
      expect(find.text('Subscribe'), findsNothing);
    });

    testWidgets('Pro users see Manage subscription, not the plans', (t) async {
      phone(t);
      const pro = Entitlement(tier: Tier.pro, enforced: true);
      await t.pumpWidget(host(FakeBilling(plans: [monthlyPlan]), pro));
      await t.pumpAndSettle();
      await scrollTo(t, find.text('Manage subscription'));
      expect(find.text('Subscribe'), findsNothing);
      expect(find.text('Restore purchases'), findsNothing);
    });

    for (final lang in AppLanguage.values) {
      for (final scale in [1.0, 1.6]) {
        testWidgets('long messages fit (${lang.code}, ${scale}x)', (t) async {
          phone(t);
          final gw = FakeBilling(plans: [monthlyPlan, yearlyPlan]);
          await t.pumpWidget(host(gw, free, lang: lang, scale: scale));
          await t.pumpAndSettle();
          // the longest message, with the spinner showing
          gw.emit([
            const PurchaseUpdate(
              stage: PurchaseStage.purchased,
              productId: 'gellsoft_pro',
              token: 'x',
            ),
          ]);
          await t.pump(const Duration(milliseconds: 50));
          await scrollTo(t, find.text(tr('Restore purchases')));
          await t.pump(const Duration(milliseconds: 100));
          expect(t.takeException(), isNull);
          await t.pumpAndSettle(const Duration(seconds: 1));
          expect(t.takeException(), isNull);
        });
      }
    }
  });
}

class _NoBookings extends BookingQuotaRepo {
  @override
  Future<int> bookingsInMonth(DateTime now) async => 0;
}

class _Fixed extends LicenseNotifier {
  _Fixed(this.e);
  final Entitlement e;
  @override
  Future<LicenseState> build() async => LicenseState(
    entitlement: e,
    installId: fixtureInstallId,
    now: DateTime(2026, 5, 10),
  );
}
