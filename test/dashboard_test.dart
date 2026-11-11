import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/format.dart';
import 'package:gellsoft_rentpro/data/dashboard_repo.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;
  final today = DateTime(2027, 3, 10);
  int ms(int plusDays) =>
      DateTime(today.year, today.month, today.day + plusDays)
          .millisecondsSinceEpoch;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rentpro_db');
    AppDatabase.pathOverride = '${dir.path}/test.db';
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AppDatabase.pathOverride = null;
    await dir.delete(recursive: true);
  });

  Future<int> addBooking({
    required int pickup,
    required int event,
    required int ret,
    String status = 'booked',
    double rent = 1000,
    double discount = 0,
    int? created,
  }) async {
    final d = await AppDatabase.instance.db;
    final n = DateTime.now().microsecondsSinceEpoch;
    final cid = await d.insert('customers', {
      'uuid': 'c$n$pickup$event',
      'updated_at': n,
      'name': 'Anu',
      'created_at': n,
    });
    return d.insert('bookings', {
      'uuid': 'b$n$pickup$event$ret',
      'updated_at': n,
      'number': 1,
      'customer_id': cid,
      'event_date': ms(event),
      'pickup_date': ms(pickup),
      'return_date': ms(ret),
      'status': status,
      'rent_total': rent,
      'payable': rent - discount,
      'discount': discount,
      'created_at': created ?? ms(0),
    });
  }

  Future<void> pay(int booking, String kind, double amount, int day) async {
    final d = await AppDatabase.instance.db;
    await d.insert('payments', {
      'booking_id': booking,
      'kind': kind,
      'amount': amount,
      'paid_at': ms(day),
    });
  }

  test('an empty shop shows zeros', () async {
    final c = await DashboardRepo().counts(today);
    expect(c.pickupsToday, 0);
    expect(c.returnsToday, 0);
    expect(c.overdueReturns, 0);
    expect(c.eventsThisWeek, 0);
    expect(c.balanceDue, 0);
    expect(c.collectedThisMonth, 0);
  });

  test('counts pickups, returns, overdue and events', () async {
    await addBooking(pickup: 0, event: 2, ret: 3); // pickup today
    await addBooking(pickup: -2, event: -1, ret: 0, status: 'picked_up');
    await addBooking(pickup: -5, event: -4, ret: -2, status: 'picked_up');
    await addBooking(pickup: 4, event: 6, ret: 7); // event within the week
    await addBooking(pickup: 8, event: 9, ret: 10); // beyond the week
    await addBooking(pickup: 0, event: 1, ret: 2, status: 'cancelled');
    final c = await DashboardRepo().counts(today);
    expect(c.pickupsToday, 1, reason: 'cancelled is not counted');
    expect(c.returnsToday, 1);
    expect(c.overdueReturns, 1);
    expect(c.eventsThisWeek, 2, reason: 'today+2 and today+6, not +9');
  });

  test('balance is rent minus discount minus rent payments, deposits apart',
      () async {
    final a = await addBooking(pickup: 1, event: 2, ret: 3, rent: 2000, discount: 200);
    await pay(a, 'advance', 500, 0);
    await pay(a, 'deposit', 3000, 0); // a deposit is not rent
    final b = await addBooking(pickup: 1, event: 2, ret: 3, rent: 1000);
    await pay(b, 'advance', 1000, 0);
    await addBooking(pickup: 1, event: 2, ret: 3, rent: 9999, status: 'cancelled');
    final c = await DashboardRepo().counts(today);
    expect(c.balanceDue, 1300); // 2000 - 200 - 500, and nothing for b
  });

  test('collected this month counts rent payments of this month only', () async {
    final a = await addBooking(pickup: 1, event: 2, ret: 3);
    await pay(a, 'advance', 400, 0);
    await pay(a, 'balance', 100, 1);
    await pay(a, 'deposit', 5000, 0);
    await pay(a, 'advance', 700, -20); // last month
    final c = await DashboardRepo().counts(today);
    expect(c.collectedThisMonth, 500);
  });

  test('day helpers', () {
    expect(dayOf(DateTime(2027, 3, 10, 18, 30)), DateTime(2027, 3, 10));
    expect(monthStart(DateTime(2027, 3, 10)), DateTime(2027, 3));
  });
}
