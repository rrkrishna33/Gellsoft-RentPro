import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/device.dart';
import 'package:gellsoft_rentpro/core/theme.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:gellsoft_rentpro/subscription/clock_gate.dart';
import 'package:gellsoft_rentpro/subscription/license_client.dart';
import 'package:gellsoft_rentpro/subscription/license_state.dart';
import 'package:gellsoft_rentpro/subscription/license_sync.dart';
import 'package:gellsoft_rentpro/subscription/license_token.dart';
import 'package:gellsoft_rentpro/subscription/plan.dart';
import 'package:gellsoft_rentpro/subscription/trusted_clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_device.dart';
import 'license_fixtures.dart';

final key = publicKeyFromPem(fixturePublicKeyPem);

/// The server's time on the signed sample license.
final issued = DateTime.fromMillisecondsSinceEpoch(fixtureIssuedAt * 1000);

/// A pretend server that always answers with the sample trial license.
class _Api implements LicenseApi {
  final calls = <String?>[]; // the phone id sent each time
  bool offline = false;

  /// Which sample license the server answers with.
  String reply = 'trial';

  @override
  Future<String> refresh({
    required String installId,
    required String appVersion,
    String? purchaseToken,
    String? deviceId,
  }) async {
    calls.add(deviceId);
    if (offline) throw const LicenseUnavailable('offline');
    return fixtureTokens[reply]!;
  }
}

class _Fixed extends LicenseNotifier {
  _Fixed(this.enforced);
  final bool enforced;
  @override
  Future<LicenseState> build() async => LicenseState(
    entitlement: Entitlement(tier: Tier.free, enforced: enforced),
    installId: fixtureInstallId,
    now: issued,
  );
}

const ref = ClockReference(
  serverMs: 1000000000000,
  localMs: 1000000000000,
  monoMs: 5000,
  bootCount: 7,
);
final base = DateTime.fromMillisecondsSinceEpoch(ref.serverMs);

ClockInfo info(Duration since, {int boot = 7, bool? auto = true}) => ClockInfo(
  elapsedMs: ref.monoMs! + since.inMilliseconds,
  bootCount: boot,
  autoTime: auto,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      LicenseStore.installIdKey: fixtureInstallId,
    });
  });
  tearDown(() => Lang.current = AppLanguage.en);

  group('is the phone\'s time right?', () {
    test('nothing to compare with is not a problem', () {
      final s = assessClock(
        reference: null,
        localNow: base,
        info: info(Duration.zero),
      );
      expect(s.problem, ClockProblem.none);
      expect(s.verified, isFalse);
      expect(s.now, base);

      // not an Android phone
      final t = assessClock(reference: ref, localNow: base, info: null);
      expect(t.problem, ClockProblem.none);
      expect(t.verified, isFalse);

      // a reference that could not read the elapsed-time clock
      const noMono = ClockReference(serverMs: 1, localMs: 1);
      expect(
        assessClock(
          reference: noMono,
          localNow: base,
          info: info(Duration.zero),
        ).ok,
        isTrue,
      );
    });

    test('time passing normally is fine, and the trusted time follows it', () {
      const hour = Duration(hours: 1);
      final s = assessClock(
        reference: ref,
        localNow: base.add(hour),
        info: info(hour),
      );
      expect(s.ok, isTrue);
      expect(s.verified, isTrue);
      expect(s.now, base.add(hour));
      expect(s.skew!.inSeconds, 0);
    });

    test('moving the date forward is noticed', () {
      const hour = Duration(hours: 1);
      final s = assessClock(
        reference: ref,
        localNow: base.add(hour + const Duration(days: 31)),
        info: info(hour),
      );
      expect(s.problem, ClockProblem.changed);
      expect(s.now, base.add(hour)); // the real time, not the phone's
      expect(s.skew!.inDays, 31);
    });

    test('moving the date back is noticed too', () {
      const hour = Duration(hours: 1);
      final s = assessClock(
        reference: ref,
        localNow: base.add(hour - const Duration(hours: 5)),
        info: info(hour),
      );
      expect(s.problem, ClockProblem.changed);
      expect(s.skew!.inHours, -5);
    });

    test('a few minutes of drift is allowed, more is not', () {
      const hour = Duration(hours: 1);
      ClockStatus at(Duration drift) => assessClock(
        reference: ref,
        localNow: base.add(hour + drift),
        info: info(hour),
      );
      expect(at(const Duration(minutes: 4, seconds: 59)).ok, isTrue);
      expect(at(const Duration(minutes: 5)).ok, isTrue);
      expect(at(const Duration(minutes: 5, seconds: 1)).ok, isFalse);
      expect(at(const Duration(minutes: -5, seconds: -1)).ok, isFalse);
    });

    test(
      'a restart cannot be measured: fine on Automatic time, not otherwise',
      () {
        final later = base.add(const Duration(days: 2));
        expect(
          assessClock(
            reference: ref,
            localNow: later,
            info: info(const Duration(seconds: 30), boot: 8, auto: true),
          ).ok,
          isTrue,
        );
        final off = assessClock(
          reference: ref,
          localNow: later,
          info: info(const Duration(seconds: 30), boot: 8, auto: false),
        );
        expect(off.problem, ClockProblem.unverifiable);
        expect(off.verified, isFalse);
        // a phone that will not say is given the benefit of the doubt
        expect(
          assessClock(
            reference: ref,
            localNow: later,
            info: info(const Duration(seconds: 30), boot: 8, auto: null),
          ).ok,
          isTrue,
        );
      },
    );

    test('Automatic time being off does not matter while nothing changed', () {
      const hour = Duration(hours: 1);
      expect(
        assessClock(
          reference: ref,
          localNow: base.add(hour),
          info: info(hour, auto: false),
        ).ok,
        isTrue,
      );
    });

    test('a phone with no restart count is treated as restarted', () {
      const hour = Duration(hours: 1);
      final s = assessClock(
        reference: ref,
        localNow: base.add(hour),
        info: ClockInfo(
          elapsedMs: ref.monoMs! + hour.inMilliseconds,
          autoTime: false,
        ),
      );
      expect(s.problem, ClockProblem.unverifiable);
    });
  });

  group('the phone id', () {
    test(
      'is scrambled: the same every time, 64 hex characters, not the id',
      () {
        final a = scrambleDeviceId('9774d56d682e549c');
        expect(a, scrambleDeviceId('9774d56d682e549c'));
        expect(a, isNot(scrambleDeviceId('9774d56d682e549d')));
        expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(a, isNot(contains('9774d56d682e549c')));
      },
    );

    test('a plain computer has no phone id and no clock facts', () async {
      final d = PlatformDeviceInfo();
      expect(await d.deviceId(), isNull);
      expect(await d.clock(), isNull);
      await d.openDateSettings(); // does nothing, does not throw
    });
  });

  group('the license check', () {
    late _Api api;
    late FakeDevice device;
    late LicenseSync sync;
    late DateTime now;

    setUp(() {
      api = _Api();
      device = FakeDevice();
      now = issued.add(const Duration(seconds: 2));
      sync = LicenseSync(
        api: api,
        store: LicenseStore(publicKey: key),
        publicKey: key,
        appVersion: '9.9.9',
        clock: () => now,
        device: device,
      );
    });

    test('sends the scrambled phone id', () async {
      await sync.refresh();
      expect(api.calls.single, device.id);
      expect(api.calls.single, hasLength(64));
    });

    test('a phone that will not say its id sends none', () async {
      device.id = null;
      await sync.refresh();
      expect(api.calls.single, isNull);
    });

    test('before any check there is nothing to compare', () async {
      final s = await sync.clockStatus();
      expect(s.ok, isTrue);
      expect(s.verified, isFalse);
    });

    test('after a check, normal time is verified', () async {
      await sync.refresh();
      device.pass(const Duration(hours: 3));
      now = now.add(const Duration(hours: 3));
      final s = await sync.clockStatus();
      expect(s.ok, isTrue);
      expect(s.verified, isTrue);
      expect(s.now.difference(issued).inHours, 3);
    });

    test('changing the date afterwards is caught, offline', () async {
      await sync.refresh();
      api.offline = true;
      device.pass(const Duration(hours: 1));
      now = now.add(
        const Duration(hours: 1, days: 30),
      ); // the user jumps a month
      final s = await sync.clockStatus();
      expect(s.problem, ClockProblem.changed);
      expect(s.skew!.inDays, 30);
      expect(s.now.difference(issued).inHours, 1); // the real time
    });

    test(
      'a phone whose date was already wrong at the check is caught',
      () async {
        now = issued.add(const Duration(days: 3));
        await sync.refresh();
        expect((await sync.clockStatus()).problem, ClockProblem.changed);
      },
    );

    test('correcting the date clears it, with no new check needed', () async {
      now = issued.add(const Duration(days: 3));
      await sync.refresh();
      expect((await sync.clockStatus()).ok, isFalse);
      now = issued.add(const Duration(seconds: 3)); // set right again
      expect((await sync.clockStatus()).ok, isTrue);
    });

    test(
      'after a restart with Automatic time off, a check online settles it',
      () async {
        await sync.refresh();
        device
          ..restart()
          ..setAutoTime(false);
        now = now.add(const Duration(hours: 5));
        expect((await sync.clockStatus()).problem, ClockProblem.unverifiable);

        now = issued.add(const Duration(seconds: 5));
        await sync.refresh(); // online: the server's time is known again
        expect((await sync.clockStatus()).ok, isTrue);
      },
    );

    test('a failed check keeps what the app already knew', () async {
      await sync.refresh();
      api.offline = true;
      await sync.refresh();
      device.pass(const Duration(hours: 1));
      now = now.add(const Duration(hours: 1));
      expect((await sync.clockStatus()).verified, isTrue);
    });
  });

  group('renewing the license while the app stays open', () {
    late _Api api;
    late FakeDevice device;
    late LicenseSync sync;
    late DateTime now;

    setUp(() {
      api = _Api();
      device = FakeDevice();
      now = issued.add(const Duration(seconds: 2));
      sync = LicenseSync(
        api: api,
        store: LicenseStore(publicKey: key),
        publicKey: key,
        appVersion: '9.9.9',
        clock: () => now,
        device: device,
      );
    });

    test('with no license yet, one is needed', () async {
      expect(await sync.needsRenewal(), isTrue);
    });

    test('a new trial or free license is left alone', () async {
      await sync.refresh();
      expect(await sync.needsRenewal(), isFalse);
      now = issued.add(const Duration(minutes: 14));
      expect(await sync.needsRenewal(), isFalse);
    });

    test('a license older than 15 minutes is renewed', () async {
      await sync.refresh();
      now = issued.add(const Duration(minutes: 16));
      expect(await sync.needsRenewal(), isTrue);
    });

    test('Pro with time left is left alone', () async {
      api.reply = 'pro';
      await sync.refresh();
      now = issued.add(const Duration(minutes: 10));
      expect(await sync.needsRenewal(), isFalse);
    });

    test('Pro whose period has run out is renewed', () async {
      api.reply = 'proEndsSoon'; // Pro for one hour
      await sync.refresh();
      now = issued.add(const Duration(minutes: 10));
      expect(await sync.needsRenewal(), isFalse); // fresh, Pro still running
      now = issued.add(const Duration(hours: 2));
      expect(await sync.needsRenewal(), isTrue);
    });

    test('a renewal that works brings the new period in', () async {
      api.reply = 'proEndsSoon';
      await sync.refresh();
      now = issued.add(const Duration(hours: 2));
      api.reply = 'pro'; // the subscription renewed: Pro for a month
      expect(await sync.renewIfNeeded(), isTrue);
      final state = await LicenseStore(publicKey: key).load(now);
      expect(state.entitlement.tier, Tier.pro);
    });

    test('it does not ask when nothing is due', () async {
      await sync.refresh();
      final before = api.calls.length;
      expect(await sync.renewIfNeeded(), isFalse);
      expect(api.calls.length, before);
    });

    test(
      'an unreachable server is not asked again every few seconds',
      () async {
        api.reply = 'proEndsSoon';
        await sync.refresh();
        now = issued.add(const Duration(hours: 2));
        api.offline = true;
        final before = api.calls.length;

        expect(await sync.renewIfNeeded(), isFalse); // tried, failed
        expect(api.calls.length, before + 1);

        now = now.add(const Duration(minutes: 1));
        expect(await sync.renewIfNeeded(), isFalse); // too soon: not tried
        expect(api.calls.length, before + 1);

        now = now.add(
          const Duration(minutes: 5),
        ); // after the wait: tries again
        api.offline = false;
        api.reply = 'pro';
        expect(await sync.renewIfNeeded(), isTrue);
        expect(api.calls.length, before + 2);
      },
    );

    test('the clock guard does it by itself, once', () async {
      api.reply = 'proEndsSoon';
      await sync.refresh();
      now = issued.add(const Duration(hours: 2));
      device.pass(const Duration(hours: 2)); // the phone's clock is fine
      final before = api.calls.length;

      final c = ProviderContainer(
        overrides: [
          licenseSyncProvider.overrideWithValue(sync),
          deviceInfoProvider.overrideWithValue(device),
          licenseProvider.overrideWith(() => _Fixed(true)),
        ],
      );
      addTearDown(c.dispose);
      c.read(clockGuardProvider);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(api.calls.length, before + 1); // renewed on its own
      await c.read(clockGuardProvider.notifier).check();
      expect(api.calls.length, before + 1); // and not again straight away
    });
  });

  group('the clock on screen', () {
    late _Api api;
    late FakeDevice device;
    late DateTime now;

    Widget app({
      bool enforced = true,
      AppLanguage lang = AppLanguage.en,
      double scale = 1,
      Widget? child,
    }) {
      Lang.current = lang;
      final sync = LicenseSync(
        api: api,
        store: LicenseStore(publicKey: key),
        publicKey: key,
        appVersion: '9.9.9',
        clock: () => now,
        device: device,
      );
      return ProviderScope(
        overrides: [
          licenseSyncProvider.overrideWithValue(sync),
          deviceInfoProvider.overrideWithValue(device),
          licenseProvider.overrideWith(() => _Fixed(enforced)),
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
          builder: (context, c) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: ClockGate(child: c!),
          ),
          home: child ?? const Scaffold(body: Center(child: Text('the app'))),
        ),
      );
    }

    Future<void> seed() async {
      // a server check has happened, with the phone's time right
      final sync = LicenseSync(
        api: api,
        store: LicenseStore(publicKey: key),
        publicKey: key,
        clock: () => issued.add(const Duration(seconds: 1)),
        device: device,
      );
      await sync.refresh();
    }

    void phone(WidgetTester t, {double height = 1400}) {
      t.view.physicalSize = Size(360 * 3, height * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
    }

    Future<void> close(WidgetTester t) async {
      // stops the guard's timer
      await t.pumpWidget(const SizedBox());
    }

    setUp(() {
      api = _Api();
      device = FakeDevice();
      now = issued.add(const Duration(seconds: 2));
    });

    testWidgets('the date and time show at the top, and the app is usable', (
      t,
    ) async {
      phone(t);
      await t.runAsync(seed);
      await t.pumpWidget(app());
      await t.pump(const Duration(milliseconds: 200));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('2026'), findsOneWidget); // the clock strip
      expect(find.byIcon(Icons.verified_outlined), findsOneWidget);
      expect(find.text('the app'), findsOneWidget);
      expect(
        find.text('The date and time on this phone is not correct'),
        findsNothing,
      );
      await close(t);
    });

    testWidgets('a changed date stops the app until it is corrected', (
      t,
    ) async {
      phone(t);
      await t.runAsync(seed);
      now = issued.add(const Duration(days: 40)); // the user jumps ahead
      await t.pumpWidget(app());
      await t.pump(const Duration(milliseconds: 200));
      await t.pump(const Duration(milliseconds: 200));

      expect(
        find.text('The date and time on this phone is not correct'),
        findsOneWidget,
      );
      expect(find.text('Correct time'), findsOneWidget);
      expect(find.text('Phone time'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

      // the phone time is set right again, then "Check again"
      now = issued.add(const Duration(seconds: 5));
      await t.tap(find.text('Check again'));
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 300));
      expect(
        find.text('The date and time on this phone is not correct'),
        findsNothing,
      );
      expect(find.text('the app'), findsOneWidget);
      expect(api.calls, isNotEmpty); // it asked the server too
      await close(t);
    });

    testWidgets('still wrong after "Check again" says so', (t) async {
      phone(t);
      await t.runAsync(seed);
      now = issued.add(const Duration(days: 40));
      await t.pumpWidget(app());
      await t.pump(const Duration(milliseconds: 200));
      await t.pump(const Duration(milliseconds: 200));
      await t.tap(find.text('Check again'));
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 300));
      expect(
        find.text(
          'The time is still not correct. Fix it in settings, then check again.',
        ),
        findsOneWidget,
      );
      await close(t);
    });

    testWidgets('the settings button opens the phone\'s date settings', (
      t,
    ) async {
      phone(t);
      await t.runAsync(seed);
      now = issued.add(const Duration(days: 40));
      await t.pumpWidget(app());
      await t.pump(const Duration(milliseconds: 200));
      await t.pump(const Duration(milliseconds: 200));
      await t.tap(find.text('Open date & time settings'));
      await t.pump();
      expect(device.settingsOpened, 1);
      await close(t);
    });

    testWidgets('before the paywall is on, a wrong date only shows a warning', (
      t,
    ) async {
      phone(t);
      await t.runAsync(seed);
      now = issued.add(const Duration(days: 40));
      await t.pumpWidget(app(enforced: false));
      await t.pump(const Duration(milliseconds: 200));
      await t.pump(const Duration(milliseconds: 200));
      expect(
        find.text('The date and time on this phone is not correct'),
        findsNothing,
      );
      expect(find.text('the app'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      await close(t);
    });

    testWidgets('a restart with Automatic time off explains what to do', (
      t,
    ) async {
      phone(t);
      await t.runAsync(seed);
      device
        ..restart()
        ..setAutoTime(false);
      api.offline = true;
      await t.pumpWidget(app());
      await t.pump(const Duration(milliseconds: 200));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('The phone was restarted'), findsOneWidget);
      expect(find.text('Correct time'), findsNothing); // nothing is known
      await close(t);
    });

    for (final lang in AppLanguage.values) {
      testWidgets(
        'the stop screen fits a small phone, large text (${lang.code})',
        (t) async {
          phone(t, height: 640);
          await t.runAsync(seed);
          now = issued.add(const Duration(days: 40));
          await t.pumpWidget(app(lang: lang, scale: 1.6));
          await t.pump(const Duration(milliseconds: 200));
          await t.pump(const Duration(milliseconds: 200));
          expect(t.takeException(), isNull);
          expect(find.byType(FilledButton), findsOneWidget);
          await close(t);
        },
      );
    }
  });
}
