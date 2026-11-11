import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/booking_math.dart';
import 'package:gellsoft_rentpro/data/booking_models.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/csv_export.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/invoice_repo.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/report_repo.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DateTime day(int d) => DateTime(2027, 3, d);
DateRange march() => (from: DateTime(2027, 3), to: DateTime(2027, 4));

void main() {
  late Directory dir;
  final bookings = BookingRepo();
  final invoices = InvoiceRepo();
  final items = ItemRepo();
  final customers = CustomerRepo();
  late int anu, ravi, gown, tent;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rentpro_reports');
    AppDatabase.pathOverride = '${dir.path}/t.db';
    anu = await customers.save(Customer(name: 'Anu', phone: '9000000001', stateCode: '33', createdAt: DateTime(2027)));
    ravi = await customers.save(Customer(
      name: '=1+1 Traders',
      phone: '9000000002',
      gstin: '29ABCDE1234F1Z5',
      createdAt: DateTime(2027),
    ));
    gown = await items.save(RentItem(name: 'Gown, red', rate: 1000, hsn: '9973', gstRate: 18, deposit: 500, createdAt: DateTime(2027)));
    tent = await items.save(RentItem(name: 'Tent', rate: 400, rateType: RateType.day, hsn: '9973', gstRate: 5, createdAt: DateTime(2027)));
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AppDatabase.pathOverride = null;
    await dir.delete(recursive: true);
  });

  const gstOn = GstConfig(enabled: true);

  Future<int> book(int customer, List<int> ids, int event,
      {double advance = 0, GstConfig gst = gstOn}) =>
      bookings.create(
        BookingDraft(
          customerId: customer,
          eventDate: day(event),
          pickupDate: day(event - 1),
          returnDate: day(event + 1),
          itemIds: ids,
        ),
        isPro: true,
        advance: advance,
        gst: gst,
        now: day(1),
      );

  Future<int> inv(int b, {String at = '33', int on = 20}) => invoices.createForBooking(
    b,
    shopStateCode: at,
    prefix: 'RNT',
    gstEnabled: true,
    taxInclusive: false,
    now: day(on),
  );

  group('ranges', () {
    test('financial year runs April to March', () {
      final fy = thisFinancialYearRange(DateTime(2027, 2, 10));
      expect(fy.from, DateTime(2026, 4));
      expect(fy.to, DateTime(2027, 4));
      expect(thisFinancialYearRange(DateTime(2027, 4, 1)).from, DateTime(2027, 4));
      expect(lastFinancialYearRange(DateTime(2027, 5, 1)).from, DateTime(2026, 4));
    });

    test('months', () {
      expect(thisMonthRange(DateTime(2027, 12, 5)).to, DateTime(2028, 1));
      expect(lastMonthRange(DateTime(2027, 1, 5)).from, DateTime(2026, 12));
      expect(todayRange(DateTime(2027, 3, 5, 14)).from, DateTime(2027, 3, 5));
    });
  });

  group('summary', () {
    test('an empty shop', () async {
      final s = await ReportRepo().summary(march());
      expect(s.bookings, 0);
      expect(s.billed, 0);
      expect(s.topItems, isEmpty);
    });

    test('figures for the period', () async {
      final a = await book(anu, [gown], 10, advance: 500); // 1180, tax 180
      await book(ravi, [gown, tent], 14); // 1180 + (1200 + 60 tax) = 2440, tax 240
      await book(anu, [tent], 25, gst: GstConfig.off); // 1200, no tax
      final cancelled = await book(anu, [tent], 5);
      await bookings.cancel(cancelled);
      await book(anu, [gown], 30); // 1180, tax 180
      await bookings.addPayment(a, kind: PaymentKind.deposit, amount: 300);
      final s = await ReportRepo().summary(march());
      expect(s.bookings, 4);
      expect(s.cancelled, 1);
      expect(s.billed, 6000);
      expect(s.tax, 600);
      expect(s.collected, 500);
      expect(s.outstanding, 5500);
      expect(s.depositsHeld, 300);
      expect(s.topItems.first.name, 'Gown, red');
      expect(s.topItems.first.count, 3);
      expect(s.topItems.first.amount, 3540);
      expect(s.topItems.map((i) => i.count).reduce((a, b) => a + b), 5);
      expect(s.topCustomers.first.name, 'Anu');
      expect(s.topCustomers.first.count, 3);
      expect(s.topCustomers.first.amount, 3560);
    });

    test('bookings are placed by event date', () async {
      await book(anu, [gown], 10);
      final april = (from: DateTime(2027, 4), to: DateTime(2027, 5));
      expect((await ReportRepo().summary(april)).bookings, 0);
      expect((await ReportRepo().summary(march())).bookings, 1);
    });

    test('collected counts payments by the day they were taken', () async {
      final a = await book(anu, [gown], 10);
      await bookings.addPayment(a, kind: PaymentKind.advance, amount: 400, at: day(3));
      await bookings.addPayment(a, kind: PaymentKind.balance, amount: 100, at: DateTime(2027, 4, 2));
      expect((await ReportRepo().summary(march())).collected, 400);
      expect((await ReportRepo().summary((from: DateTime(2027, 4), to: DateTime(2027, 5)))).collected, 100);
    });
  });

  group('csv', () {
    String text(List<int> bytes) => utf8.decode(bytes);

    test('starts with a byte-order mark and ends with a line break', () async {
      final bytes = await CsvExport().build(CsvKind.bookings, march());
      expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      expect(text(bytes).endsWith('\r\n'), isTrue);
    });

    test('file names say what and when', () {
      expect(
        CsvExport.fileName(CsvKind.invoices, march()),
        'gellsoft-rentpro-invoices-2027-03-01_to_2027-03-31.csv',
      );
    });

    test('text that could be a formula, or has commas, is made safe', () {
      expect(csvText('=1+1'), "'=1+1");
      expect(csvText('Gown, red'), '"Gown, red"');
      expect(csvText('say "hi"'), '"say ""hi"""');
      expect(csvText(null), '');
      expect(csvNum(12.5), '12.50');
    });

    test('bookings sheet', () async {
      final a = await book(anu, [gown, tent], 10, advance: 500);
      await bookings.addPayment(a, kind: PaymentKind.deposit, amount: 200);
      final lines = await CsvExport().bookings(march());
      expect(lines.first.startsWith('Booking no,Customer,Phone,Event date'), isTrue);
      expect(lines.length, 2);
      final row = lines[1];
      expect(row, contains('Anu'));
      expect(row, contains('2027-03-10'));
      expect(row, contains('"Gown, red; Tent"'));
      expect(row, contains(csvNum(2440 - 500)), reason: 'balance');
      expect(row, contains(csvNum(200)), reason: 'deposit held');
    });

    test('payments sheet shows a refund as negative', () async {
      final a = await book(anu, [gown], 10, advance: 300);
      await bookings.addPayment(a, kind: PaymentKind.deposit, amount: 500, at: day(10));
      await bookings.addPayment(a, kind: PaymentKind.refund, amount: 100, at: day(12));
      final lines = await CsvExport().payments(march());
      expect(lines.length, 4);
      expect(lines.where((l) => l.contains('refund')).single, contains('-100.00'));
      expect(lines.where((l) => l.contains('advance')).single, contains('300.00'));
    });

    test('invoices (sales register) lists tax and status', () async {
      final a = await book(anu, [gown], 10);
      final b = await book(ravi, [gown], 14);
      await inv(a, on: 20);
      final second = await inv(b, on: 21);
      await invoices.cancel(second);
      final lines = await CsvExport().invoices(march());
      expect(lines.length, 3);
      expect(lines[1], contains('RNT-0001'));
      expect(lines[1], contains('Tax invoice'));
      expect(lines[1], contains('Active'));
      expect(lines[1], contains('90.00,90.00,0.00,1180.00'));
      expect(lines[2], contains('Cancelled'));
      expect(lines[2], contains("'=1+1 Traders"));
    });

    test('GSTR-1 B2B only has customers with a GSTIN, split by rate', () async {
      final a = await book(anu, [gown], 10); // no GSTIN: not B2B
      final b = await book(ravi, [gown, tent], 14); // GSTIN, two rates
      await inv(a, on: 20);
      await inv(b, on: 21);
      final lines = await CsvExport(ownState: '33').gstr1B2b(march());
      expect(lines.length, 3, reason: 'header and the two rates of one invoice');
      expect(lines[1], contains('29ABCDE1234F1Z5'));
      expect(lines[1], contains('29-Karnataka'));
      expect(lines.join('\n'), contains('18.00'));
      expect(lines.join('\n'), contains('5.00'));
      // another state: IGST carries the tax, CGST and SGST are zero
      expect(lines[1], endsWith('5.00,1200.00,60.00,0.00,0.00'));
      expect(lines[2], endsWith('18.00,1000.00,180.00,0.00,0.00'));
    });

    test('GSTR-1 B2C totals walk-in invoices by state and rate', () async {
      final a = await book(anu, [gown], 10);
      final c = await customers.save(Customer(name: 'Walk in', createdAt: DateTime(2027)));
      final b = await book(c, [gown], 14);
      await inv(a, on: 20);
      await inv(b, on: 21);
      final lines = await CsvExport(ownState: '33').gstr1B2c(march());
      expect(lines.length, 2, reason: 'both are state 33 at 18%, so one row');
      expect(lines[1], startsWith('OE,33-Tamil Nadu,18.00,2000.00,0.00,180.00,180.00'));
    });

    test('HSN summary groups by code and rate', () async {
      final a = await book(anu, [gown, tent], 10);
      await inv(a, on: 20);
      final lines = await CsvExport().gstr1Hsn(march());
      expect(lines.length, 3);
      expect(lines.join('\n'), contains('9973,Rental of goods,OTH-OTHERS'));
    });

    test('a cancelled invoice leaves the GST sheets', () async {
      final a = await book(ravi, [gown], 10);
      final id = await inv(a, on: 20);
      await invoices.cancel(id);
      expect((await CsvExport().gstr1B2b(march())).length, 1);
      expect((await CsvExport().gstr1Hsn(march())).length, 1);
    });

    test('customers sheet shows what they owe', () async {
      await book(anu, [gown], 10, advance: 400);
      final lines = await CsvExport().customers();
      final row = lines.firstWhere((l) => l.startsWith('Anu'));
      expect(row, contains('1180.00'));
      expect(row, contains('780.00'));
    });

    test('items sheet counts bookings in the period', () async {
      await book(anu, [gown], 10);
      await book(ravi, [gown], 15);
      final lines = await CsvExport().items(march());
      final row = lines.firstWhere((l) => l.contains('Gown, red'));
      expect(row, contains(',2,2360.00'));
      final tentRow = lines.firstWhere((l) => l.startsWith('Tent'));
      expect(tentRow, endsWith(',0,0.00'));
    });
  });
}
