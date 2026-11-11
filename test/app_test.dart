import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/theme.dart';
import 'package:gellsoft_rentpro/data/booking_models.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/dashboard_repo.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
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

class _NoBookings extends BookingRepo {
  @override
  Future<List<Booking>> list({
    BookingFilter filter = BookingFilter.upcoming,
    String query = '',
  }) async => const [];

  @override
  Future<List<Booking>> forReminders() async => const [];

  @override
  Future<int> freeLeft([DateTime? now]) async => 12;

  @override
  Future<Map<int, ItemConflict>> conflicts({
    required List<int> itemIds,
    required DateTime pickup,
    required DateTime ret,
    int? exceptBookingId,
    DateTime? now,
  }) async => const {};
}

class _NoItems extends ItemRepo {
  @override
  Future<List<RentItem>> list({
    String query = '',
    bool includeRetired = false,
  }) async => const [];
}

class _NoCustomers extends CustomerRepo {
  @override
  Future<List<Customer>> list({String query = ''}) async => const [];
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

Widget app() => ProviderScope(
  overrides: [
    dashboardRepoProvider.overrideWithValue(_FakeDashboard()),
    bookingRepoProvider.overrideWithValue(_NoBookings()),
    itemRepoProvider.overrideWithValue(_NoItems()),
    customerRepoProvider.overrideWithValue(_NoCustomers()),
  ],
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
    expect(find.text('To collect'), findsOneWidget);
    expect(find.text('Out today'), findsOneWidget);
    expect(find.text('Back today'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.textContaining('4,200'), findsOneWidget);
    expect(find.textContaining('1,500'), findsOneWidget);
    expect(find.text('3'), findsOneWidget, reason: 'overdue');

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
    await t.tap(find.byIcon(Icons.visibility_outlined));
    await settle(t);
    expect(find.textContaining('4,200'), findsNothing);
    expect(find.textContaining('1,500'), findsNothing);
    expect(find.text('₹ ••••••'), findsNWidgets(2));
    await t.tap(find.byIcon(Icons.visibility_off_outlined));
    await settle(t);
    expect(find.textContaining('4,200'), findsOneWidget);
  });

  testWidgets('the floating bar moves between the pages', (t) async {
    SharedPreferences.setMockInitialValues({
      'b_name': 'Royal Costumes',
      'b_type': 'costume',
    });
    await t.pumpWidget(app());
    await settle(t);

    // the bar is drawn last, so its labels are the last of their name
    await t.tap(find.text('Bookings').last);
    await settle(t);
    expect(
      find.text('No upcoming bookings. Tap + to make one.'),
      findsOneWidget,
    );
    await t.tap(find.text('Items').last);
    await settle(t);
    expect(
      find.text('Add the things you rent out, with their rate.'),
      findsOneWidget,
    );
    await t.tap(find.text('Customers').last);
    await settle(t);
    expect(
      find.text('Add your customers to book items for them.'),
      findsOneWidget,
    );
    // the middle button makes a booking
    await t.tap(find.byTooltip('New booking'));
    await settle(t);
    expect(find.text('New booking'), findsWidgets);
    await t.pageBack();
    await settle(t);
    await t.tap(find.text('Home').last);
    await settle(t);
    expect(find.text('Collected this month'), findsOneWidget);
  });

  testWidgets('the shortcut tiles open Reminders and Settings; the menu opens', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({
      'b_name': 'Royal Costumes',
      'b_type': 'costume',
    });
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(app());
    await settle(t);

    await t.tap(find.text('Reminders'));
    await settle(t);
    expect(find.text('Nothing needs your attention right now.'), findsOneWidget);
    await t.pageBack();
    await settle(t);

    await t.tap(find.text('Settings').first);
    await settle(t);
    expect(find.text('Costume / Dress rental'), findsOneWidget);
    expect(find.textContaining('Version'), findsOneWidget);
    expect(find.text('GellSoft Pro'), findsOneWidget);
    await t.pageBack();
    await settle(t);

    await t.tap(find.byIcon(Icons.menu));
    await settle(t);
    expect(find.text('Invoices'), findsWidgets);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('GellSoft Pro'), findsOneWidget);
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
    expect(find.text('இன்று வெளியே செல்வது'), findsOneWidget);
    expect(find.text('இன்று திரும்புவது'), findsOneWidget);
  });

  test('light and dark themes carry the plum style', () {
    expect(AppTheme.light().extension<AuroraStyle>(), isNotNull);
    expect(AppTheme.dark().extension<AuroraStyle>(), isNotNull);
    expect(AppTheme.light().colorScheme.primary, Palette.primary);
    expect(AppTheme.dark().colorScheme.primary, Palette.darkPrimary);
  });
}
