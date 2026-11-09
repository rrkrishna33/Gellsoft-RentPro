import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/theme.dart';
import 'package:gellsoft_rentpro/data/dashboard_repo.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:gellsoft_rentpro/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDashboard extends DashboardRepo {
  @override
  Future<DashboardCounts> counts([DateTime? now]) async =>
      const DashboardCounts(
        pickupsToday: 2,
        returnsToday: 1,
        overdueReturns: 3,
        eventsThisWeek: 4,
        balanceDue: 1500,
        collectedThisMonth: 4200,
      );
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

Widget app() => ProviderScope(
  overrides: [dashboardRepoProvider.overrideWithValue(_FakeDashboard())],
  child: const GellsoftRentProApp(),
);

void main() {
  tearDown(() => Lang.current = AppLanguage.en);

  testWidgets('first start asks for the shop, then shows Home', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(app());
    await settle(t);

    expect(find.text('Shop name'), findsOneWidget);
    // an empty name is refused
    await t.tap(find.text('Get started'));
    await settle(t);
    expect(find.text('Enter the shop name'), findsOneWidget);

    await t.enterText(find.byType(TextFormField).first, 'Royal Costumes');
    await t.tap(find.text('Get started'));
    await settle(t);

    expect(find.text('Royal Costumes'), findsOneWidget);
    expect(find.text('Collected this month'), findsOneWidget);
    expect(find.text('Pickups today'), findsOneWidget);
    expect(find.text('Overdue returns'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // overdue
    expect(find.textContaining('4,200'), findsOneWidget);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('b_name'), 'Royal Costumes');
  });

  testWidgets('a saved shop goes straight to Home; the eye hides amounts', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({
      'b_name': 'Royal Costumes',
      'b_type': 'costume',
    });
    await t.pumpWidget(app());
    await settle(t);

    expect(find.text('Royal Costumes'), findsOneWidget);
    expect(find.textContaining('4,200'), findsOneWidget);
    await t.tap(find.byIcon(Icons.visibility));
    await settle(t);
    expect(find.textContaining('4,200'), findsNothing);
    expect(find.text('••••'), findsNWidgets(2));
    await t.tap(find.byIcon(Icons.visibility_off));
    await settle(t);
    expect(find.textContaining('4,200'), findsOneWidget);
  });

  testWidgets('the bar moves between the tabs, Settings shows the shop', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({
      'b_name': 'Royal Costumes',
      'b_type': 'costume',
    });
    await t.pumpWidget(app());
    await settle(t);

    await t.tap(find.text('Bookings'));
    await settle(t);
    expect(find.text('Bookings will appear here.'), findsOneWidget);
    await t.tap(find.text('Items'));
    await settle(t);
    expect(find.text('The things you rent out will appear here.'), findsOneWidget);
    await t.tap(find.text('Settings'));
    await settle(t);
    expect(find.text('Royal Costumes'), findsOneWidget);
    expect(find.text('Costume / Dress rental'), findsOneWidget);
    expect(find.textContaining('Version'), findsOneWidget);
  });

  testWidgets('the Tamil language shows Tamil', (t) async {
    SharedPreferences.setMockInitialValues({
      'b_name': 'Royal Costumes',
      'b_type': 'costume',
      's_lang': 'ta',
    });
    await t.pumpWidget(app());
    await settle(t);
    expect(find.text('முகப்பு'), findsOneWidget);
    expect(find.text('இன்று எடுத்துச் செல்வது'), findsOneWidget);
  });

  test('light and dark themes carry the plum style', () {
    expect(AppTheme.light().extension<RentStyle>(), isNotNull);
    expect(AppTheme.dark().extension<RentStyle>(), isNotNull);
    expect(AppTheme.light().colorScheme.primary, Palette.primary);
    expect(AppTheme.dark().colorScheme.primary, Palette.darkPrimary);
  });
}
