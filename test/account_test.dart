// Optional Google sign-in: the service that talks to Google and our server,
// and the Account screen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/theme.dart';
import 'package:gellsoft_rentpro/features/settings/account_screen.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:gellsoft_rentpro/subscription/account.dart';
import 'package:gellsoft_rentpro/subscription/license_client.dart';
import 'package:gellsoft_rentpro/subscription/license_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_device.dart';

class FakeGoogle implements GoogleLogin {
  FakeGoogle(this.token);
  String? token; // null = the person closed the chooser
  Object? error;
  int signOuts = 0;

  @override
  Future<String?> idToken() async {
    if (error != null) throw error!;
    return token;
  }

  @override
  Future<void> signOut() async => signOuts++;
}

class FakeAccountApi implements AccountApi {
  Object? error;
  final signIns = <String>[];
  final signOutsFor = <String>[];

  @override
  Future<Account> signIn({
    required String installId,
    required String idToken,
  }) async {
    if (error != null) throw error!;
    signIns.add(idToken);
    return const Account(email: 'krishna@example.com', name: 'Krishna');
  }

  @override
  Future<void> signOut({required String installId}) async {
    if (error != null) throw error!;
    signOutsFor.add(installId);
  }

  final deletes = <String>[];

  @override
  Future<void> delete({required String idToken}) async {
    if (error != null) throw error!;
    deletes.add(idToken);
  }
}

/// The license server is not reachable: refreshes quietly do nothing.
class OfflineLicense implements LicenseApi {
  @override
  Future<String> refresh({
    required String installId,
    required String appVersion,
    String? purchaseToken,
    String? deviceId,
  }) async => throw const LicenseUnavailable('test');
}

AccountService service(FakeGoogle g, FakeAccountApi a) => AccountService(
  google: g,
  api: a,
  sync: LicenseSync(api: OfflineLicense(), device: FakeDevice()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Lang.current = AppLanguage.en;
  });

  group('AccountService', () {
    test('signs in, remembers the account and sends the token', () async {
      final api = FakeAccountApi();
      final s = service(FakeGoogle('a-long-id-token-from-google'), api);
      final r = await s.signIn();
      expect(r.result, SignInResult.signedIn);
      expect(r.account!.email, 'krishna@example.com');
      expect(api.signIns, ['a-long-id-token-from-google']);
      expect((await s.current())!.email, 'krishna@example.com');
    });

    test(
      'closing the Google chooser is not an error and changes nothing',
      () async {
        final api = FakeAccountApi();
        final s = service(FakeGoogle(null), api);
        final r = await s.signIn();
        expect(r.result, SignInResult.cancelled);
        expect(api.signIns, isEmpty);
        expect(await s.current(), isNull);
      },
    );

    test('no connection to the server: not signed in, can retry', () async {
      final api = FakeAccountApi()..error = const LicenseUnavailable('x');
      final s = service(FakeGoogle('tok'), api);
      expect((await s.signIn()).result, SignInResult.offline);
      expect(await s.current(), isNull);
    });

    test('a token the server refuses is a failure', () async {
      final api = FakeAccountApi()..error = const AccountRejected();
      final s = service(FakeGoogle('tok'), api);
      expect((await s.signIn()).result, SignInResult.failed);
      expect(await s.current(), isNull);
    });

    test('Google being unavailable on the phone is a failure', () async {
      final g = FakeGoogle('tok')..error = const GoogleUnavailable('config');
      final s = service(g, FakeAccountApi());
      expect((await s.signIn()).result, SignInResult.failed);
    });

    test('signing out forgets the account and tells the server', () async {
      final api = FakeAccountApi();
      final g = FakeGoogle('tok');
      final s = service(g, api);
      await s.signIn();
      await s.signOut();
      expect(await s.current(), isNull);
      expect(g.signOuts, 1);
      expect(api.signOutsFor, hasLength(1));
    });

    test('signing out works offline too', () async {
      final api = FakeAccountApi();
      final s = service(FakeGoogle('tok'), api);
      await s.signIn();
      api.error = const LicenseUnavailable('x');
      await s.signOut();
      expect(await s.current(), isNull);
    });
  });

  group('deleting the account', () {
    test('erases it on the server and forgets it here', () async {
      final api = FakeAccountApi();
      final g = FakeGoogle('a-long-id-token-from-google');
      final s = service(g, api);
      await s.signIn();
      expect(await s.deleteAccount(), DeleteResult.deleted);
      expect(api.deletes, ['a-long-id-token-from-google']);
      expect(await s.current(), isNull);
      expect(g.signOuts, 1);
    });

    test('closing the Google chooser deletes nothing', () async {
      final api = FakeAccountApi();
      final g = FakeGoogle('a-long-id-token-from-google');
      final s = service(g, api);
      await s.signIn();
      g.token = null;
      expect(await s.deleteAccount(), DeleteResult.cancelled);
      expect(api.deletes, isEmpty);
      expect(await s.current(), isNotNull); // still signed in
    });

    test('no connection: nothing is deleted, can retry', () async {
      final api = FakeAccountApi();
      final s = service(FakeGoogle('a-long-id-token-from-google'), api);
      await s.signIn();
      api.error = const LicenseUnavailable('x');
      expect(await s.deleteAccount(), DeleteResult.offline);
      expect(await s.current(), isNotNull);
    });

    test('a refused token (wrong account) deletes nothing', () async {
      final api = FakeAccountApi();
      final s = service(FakeGoogle('a-long-id-token-from-google'), api);
      await s.signIn();
      api.error = const AccountRejected();
      expect(await s.deleteAccount(), DeleteResult.failed);
      expect(await s.current(), isNotNull);
    });
  });

  group('Account screen', () {
    Widget host(AccountService s, Widget home) => ProviderScope(
      overrides: [accountServiceProvider.overrideWithValue(s)],
      child: MaterialApp(theme: AppTheme.light(), home: home),
    );

    testWidgets('invites, signs in, then shows who is signed in', (t) async {
      final s = service(
        FakeGoogle('a-long-id-token-from-google'),
        FakeAccountApi(),
      );
      await t.pumpWidget(host(s, const AccountScreen()));
      await t.pumpAndSettle();
      expect(find.text('Sign in with Google'), findsWidgets);
      expect(find.textContaining('Billing works without signing in'), findsOne);

      await t.tap(find.widgetWithText(FilledButton, 'Sign in with Google'));
      await t.pumpAndSettle();
      expect(find.text('Krishna'), findsOneWidget);
      expect(find.text('krishna@example.com'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('signing out asks first, then returns to the invitation', (
      t,
    ) async {
      final s = service(
        FakeGoogle('a-long-id-token-from-google'),
        FakeAccountApi(),
      );
      await t.pumpWidget(host(s, const AccountScreen()));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Sign in with Google'));
      await t.pumpAndSettle();

      await t.tap(find.text('Sign out'));
      await t.pumpAndSettle();
      expect(find.text('Sign out?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.text('krishna@example.com'), findsOneWidget); // still in

      await t.tap(find.text('Sign out'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, 'Sign out'));
      await t.pumpAndSettle();
      expect(find.text('krishna@example.com'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Sign in with Google'),
        findsOneWidget,
      );
    });

    testWidgets('Delete account explains, asks, then erases and signs out', (
      t,
    ) async {
      final api = FakeAccountApi();
      final s = service(FakeGoogle('a-long-id-token-from-google'), api);
      await t.pumpWidget(host(s, const AccountScreen()));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Sign in with Google'));
      await t.pumpAndSettle();

      await t.tap(find.text('Delete account'));
      await t.pumpAndSettle();
      expect(find.text('Delete your account?'), findsOneWidget);
      expect(find.textContaining('stay on this phone'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(api.deletes, isEmpty); // backing out deletes nothing

      await t.tap(find.text('Delete account'));
      await t.pumpAndSettle();
      await t.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Delete account'),
        ),
      );
      await t.pumpAndSettle();
      expect(api.deletes, hasLength(1));
      expect(find.text('krishna@example.com'), findsNothing);
      expect(find.text('Your account was deleted'), findsOneWidget);
    });

    testWidgets('an offline sign-in says so and stays signed out', (t) async {
      final api = FakeAccountApi()..error = const LicenseUnavailable('x');
      final s = service(FakeGoogle('a-long-id-token-from-google'), api);
      await t.pumpWidget(host(s, const AccountScreen()));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Sign in with Google'));
      await t.pumpAndSettle();
      expect(find.textContaining('Could not reach the server'), findsOneWidget);
      expect(find.text('krishna@example.com'), findsNothing);
    });

    testWidgets('the Pro screen invitation goes away once signed in', (
      t,
    ) async {
      final s = service(
        FakeGoogle('a-long-id-token-from-google'),
        FakeAccountApi(),
      );
      await t.pumpWidget(host(s, const Scaffold(body: AccountPrompt())));
      await t.pumpAndSettle();
      expect(find.text('Sign in for backup and restore'), findsOneWidget);

      await s.signIn();
      final c = ProviderScope.containerOf(
        t.element(find.byType(AccountPrompt)),
      );
      c.invalidate(accountProvider);
      await t.pumpAndSettle();
      expect(find.text('Sign in for backup and restore'), findsNothing);
    });
  });
}
