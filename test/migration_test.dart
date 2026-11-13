import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/booking_math.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/invoice_repo.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The version 1 files that earlier builds of RentPro made, before GST. A
/// phone that ran one of them kept that file, and the app must still work.
const _sync = '''
  uuid TEXT NOT NULL UNIQUE,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0''';

List<String> oldSchema({required bool withBookingMoney}) => [
  '''CREATE TABLE items(
    id INTEGER PRIMARY KEY AUTOINCREMENT, $_sync,
    name TEXT NOT NULL, category TEXT NOT NULL DEFAULT '', size TEXT NOT NULL DEFAULT '',
    rate_type TEXT NOT NULL DEFAULT 'event', rate REAL NOT NULL DEFAULT 0,
    deposit REAL NOT NULL DEFAULT 0, notes TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'active', created_at INTEGER NOT NULL)''',
  '''CREATE TABLE customers(
    id INTEGER PRIMARY KEY AUTOINCREMENT, $_sync,
    name TEXT NOT NULL, phone TEXT NOT NULL DEFAULT '', address TEXT NOT NULL DEFAULT '',
    id_note TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL)''',
  '''CREATE TABLE bookings(
    id INTEGER PRIMARY KEY AUTOINCREMENT, $_sync,
    number INTEGER NOT NULL, customer_id INTEGER NOT NULL REFERENCES customers(id),
    event_date INTEGER NOT NULL, pickup_date INTEGER NOT NULL, return_date INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'booked', rent_total REAL NOT NULL DEFAULT 0,
    deposit_total REAL NOT NULL DEFAULT 0, discount REAL NOT NULL DEFAULT 0,
    notes TEXT NOT NULL DEFAULT '', remind_days INTEGER NOT NULL DEFAULT 2,
    created_at INTEGER NOT NULL)''',
  withBookingMoney
      ? '''CREATE TABLE booking_items(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          booking_id INTEGER NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
          item_id INTEGER NOT NULL REFERENCES items(id), name TEXT NOT NULL,
          rate_type TEXT NOT NULL DEFAULT 'event', rate REAL NOT NULL DEFAULT 0,
          deposit REAL NOT NULL DEFAULT 0, amount REAL NOT NULL DEFAULT 0)'''
      : '''CREATE TABLE booking_items(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          booking_id INTEGER NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
          item_id INTEGER NOT NULL REFERENCES items(id), name TEXT NOT NULL,
          rate REAL NOT NULL DEFAULT 0, deposit REAL NOT NULL DEFAULT 0)''',
  '''CREATE TABLE payments(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    booking_id INTEGER NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    kind TEXT NOT NULL, amount REAL NOT NULL, mode TEXT NOT NULL DEFAULT 'cash',
    note TEXT NOT NULL DEFAULT '', paid_at INTEGER NOT NULL)''',
  '''CREATE TABLE booking_photos(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    booking_id INTEGER NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    stage TEXT NOT NULL DEFAULT 'other', path TEXT NOT NULL, created_at INTEGER NOT NULL)''',
];

void main() {
  late Directory dir;
  late String path;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rentpro_migrate');
    path = p.join(dir.path, 'old.db');
    AppDatabase.pathOverride = path;
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AppDatabase.pathOverride = null;
    await dir.delete(recursive: true);
  });

  /// Makes a version 1 file the way an earlier build did, with some data.
  Future<void> makeOld({required bool withBookingMoney}) async {
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, v) async {
          for (final sql in oldSchema(withBookingMoney: withBookingMoney)) {
            await d.execute(sql);
          }
          await d.insert('customers', {
            'uuid': 'c1', 'updated_at': 1, 'name': 'Old customer',
            'phone': '9000000001', 'created_at': 1,
          });
          await d.insert('items', {
            'uuid': 'i1', 'updated_at': 1, 'name': 'Old gown',
            'rate': 1000, 'deposit': 500, 'created_at': 1,
          });
          await d.insert('bookings', {
            'uuid': 'b1', 'updated_at': 1, 'number': 1, 'customer_id': 1,
            'event_date': DateTime(2027, 3, 10).millisecondsSinceEpoch,
            'pickup_date': DateTime(2027, 3, 9).millisecondsSinceEpoch,
            'return_date': DateTime(2027, 3, 11).millisecondsSinceEpoch,
            'rent_total': 1000, 'discount': 100, 'created_at': 1,
          });
          await d.insert('booking_items', {
            'booking_id': 1, 'item_id': 1, 'name': 'Old gown',
            'rate': 1000, 'deposit': 500,
          });
        },
      ),
    );
    await db.close();
  }

  Future<Set<String>> columns(String table) async {
    final d = await AppDatabase.instance.db;
    return (await d.rawQuery('PRAGMA table_info($table)'))
        .map((r) => r['name'] as String)
        .toSet();
  }

  for (final newer in [false, true]) {
    test(
      'an older file (${newer ? 'with booking amounts' : 'the first build'}) is upgraded and keeps its data',
      () async {
        await makeOld(withBookingMoney: newer);
        // opening the database runs the upgrade
        expect(await columns('bookings'), containsAll(['tax_total', 'payable']));
        expect(await columns('items'), containsAll(['hsn', 'gst_rate']));
        expect(await columns('customers'), containsAll(['gstin', 'state_code']));
        expect(
          await columns('booking_items'),
          containsAll(['rate_type', 'amount', 'hsn', 'gst_rate', 'taxable', 'tax']),
        );
        final d = await AppDatabase.instance.db;
        final tables = (await d.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
            .map((r) => r['name'])
            .toSet();
        expect(tables, containsAll(['invoices', 'invoice_items']));

        // the data is still there, and the old booking owes what it did
        final b = (await BookingRepo().get(1))!;
        expect(b.customerName, 'Old customer');
        expect(b.rentTotal, 1000);
        expect(b.payable, 900, reason: 'rent less the discount');
        expect(b.balanceDue, 900);
        expect(b.lines.single.name, 'Old gown');
        expect(b.lines.single.amount, 1000);
        expect(b.lines.single.taxable, 1000);
        expect((await ItemRepo().get(1))!.name, 'Old gown');
      },
    );
  }

  test('after the upgrade a new booking with GST saves, and an invoice can be made', () async {
    await makeOld(withBookingMoney: false);
    final gown = await ItemRepo().save(
      (await ItemRepo().get(1))!.copyWith(gstRate: 18, hsn: '9973'),
    );
    final id = await BookingRepo().create(
      BookingDraft(
        customerId: 1,
        eventDate: DateTime(2027, 4, 10),
        pickupDate: DateTime(2027, 4, 9),
        returnDate: DateTime(2027, 4, 11),
        itemIds: [gown],
      ),
      isPro: true,
      advance: 100,
      gst: const GstConfig(enabled: true),
      now: DateTime(2027, 4, 1),
    );
    final b = (await BookingRepo().get(id))!;
    expect(b.taxTotal, 180);
    expect(b.payable, 1180);
    expect(b.number, 2, reason: 'numbering carries on after the old booking');
    final inv = await InvoiceRepo().createForBooking(
      id,
      shopStateCode: '33',
      prefix: 'RNT',
      gstEnabled: true,
      taxInclusive: false,
      now: DateTime(2027, 4, 12),
    );
    expect((await InvoiceRepo().get(inv))!.total, 1180);
  });

  test('an older file gets quantity, appointment time and the staff table', () async {
    await makeOld(withBookingMoney: true);
    expect(await columns('items'), contains('quantity'));
    expect(await columns('booking_items'), contains('qty'));
    expect(await columns('invoice_items'), contains('qty'));
    expect(await columns('bookings'), containsAll(['event_time', 'created_by']));
    expect(await columns('staff_users'), containsAll(['name', 'role', 'pin_hash']));
    // what was there counts as one piece, booked one at a time
    final item = (await ItemRepo().list()).single;
    expect(item.quantity, 1);
    final b = (await BookingRepo().get(1))!;
    expect(b.lines.single.qty, 1);
    expect(b.lines.single.label, 'Old gown');
    expect(b.eventTime, '');
    expect(b.createdBy, '');
    // and the old booking still blocks its item for its days
    final clash = await BookingRepo().conflicts(
      itemIds: [1],
      pickup: DateTime(2027, 3, 10),
      ret: DateTime(2027, 3, 10),
      now: DateTime(2027, 3, 1),
    );
    expect(clash.keys, [1]);
  });

  test('a new install is complete at once, and the upgrade can run twice', () async {
    final d = await AppDatabase.instance.db;
    expect(await columns('bookings'), containsAll(['tax_total', 'payable']));
    final version = (await d.rawQuery('PRAGMA user_version')).first.values.first;
    expect(version, AppDatabase.schemaVersion);
    // already complete: running the upgrade again changes nothing and does not fail
    await AppDatabase.instance.migrateTo2ForTest(d);
    await AppDatabase.instance.migrateTo2ForTest(d);
    await AppDatabase.instance.migrateTo3ForTest(d);
    await AppDatabase.instance.migrateTo3ForTest(d);
    expect(await columns('items'), containsAll(['hsn', 'gst_rate', 'quantity']));
  });

  test('the version number moves to 3', () {
    expect(AppDatabase.schemaVersion, 3);
  });
}
