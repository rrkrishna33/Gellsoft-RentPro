import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/booking_math.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/invoice_models.dart';
import 'package:gellsoft_rentpro/data/invoice_repo.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DateTime day(int d) => DateTime(2027, 3, d);

void main() {
  group('splitMoney', () {
    test('GST off: nothing is added', () {
      final m = splitMoney(
        amounts: [1000, 500],
        gstRates: [18, 18],
        discount: 0,
        gst: GstConfig.off,
      );
      expect(m.map((x) => x.tax), [0, 0]);
      expect(m.map((x) => x.total), [1000, 500]);
    });

    test('exclusive GST is added on top', () {
      final m = splitMoney(
        amounts: [1000],
        gstRates: [18],
        discount: 0,
        gst: const GstConfig(enabled: true),
      );
      expect(m.single.taxable, 1000);
      expect(m.single.tax, 180);
      expect(m.single.total, 1180);
    });

    test('inclusive GST is taken out of the amount', () {
      final m = splitMoney(
        amounts: [1180],
        gstRates: [18],
        discount: 0,
        gst: const GstConfig(enabled: true, inclusive: true),
      );
      expect(m.single.taxable, 1000);
      expect(m.single.tax, 180);
      expect(m.single.total, 1180, reason: 'the customer still pays 1180');
    });

    test('each item is taxed at its own rate', () {
      final m = splitMoney(
        amounts: [1000, 1000],
        gstRates: [5, 18],
        discount: 0,
        gst: const GstConfig(enabled: true),
      );
      expect(m[0].tax, 50);
      expect(m[1].tax, 180);
    });

    test('the discount is shared by amount and always adds up', () {
      final m = splitMoney(
        amounts: [3000, 1000, 1000],
        gstRates: [0, 0, 0],
        discount: 100,
        gst: GstConfig.off,
      );
      expect(m.map((x) => x.discount).reduce((a, b) => a + b), 100);
      expect(m[0].discount, 60);
      expect(m[1].discount, 20);
      expect(m[2].discount, 20);
      final odd = splitMoney(
        amounts: [100, 100, 100],
        gstRates: [0, 0, 0],
        discount: 10,
        gst: GstConfig.off,
      );
      expect(odd.map((x) => x.discount).reduce((a, b) => a + b), closeTo(10, 1e-9));
    });

    test('the discount lowers the taxable value', () {
      final m = splitMoney(
        amounts: [1000],
        gstRates: [18],
        discount: 100,
        gst: const GstConfig(enabled: true),
      );
      expect(m.single.taxable, 900);
      expect(m.single.tax, 162);
      expect(m.single.total, 1062);
    });

    test('a zero-rated item pays no tax', () {
      final m = splitMoney(
        amounts: [1000],
        gstRates: [0],
        discount: 0,
        gst: const GstConfig(enabled: true),
      );
      expect(m.single.tax, 0);
    });
  });

  group('bookings and invoices on a real database', () {
    late Directory dir;
    final bookings = BookingRepo();
    final invoices = InvoiceRepo();
    final items = ItemRepo();
    final customers = CustomerRepo();
    late int local, faraway, plain, dress, tent;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('rentpro_gst');
      AppDatabase.pathOverride = '${dir.path}/t.db';
      local = await customers.save(Customer(
        name: 'Anu',
        phone: '9000000001',
        address: 'Madurai',
        stateCode: '33',
        createdAt: DateTime(2027),
      ));
      faraway = await customers.save(Customer(
        name: 'Ravi Traders',
        phone: '9000000002',
        gstin: '29ABCDE1234F1Z5',
        createdAt: DateTime(2027),
      ));
      plain = await customers.save(Customer(
        name: 'Walk in',
        createdAt: DateTime(2027),
      ));
      dress = await items.save(RentItem(
        name: 'Gown',
        rate: 1000,
        hsn: '9973',
        gstRate: 18,
        deposit: 2000,
        createdAt: DateTime(2027),
      ));
      tent = await items.save(RentItem(
        name: 'Tent',
        rate: 400,
        rateType: RateType.day,
        hsn: '9973',
        gstRate: 5,
        createdAt: DateTime(2027),
      ));
    });

    tearDown(() async {
      await AppDatabase.instance.close();
      AppDatabase.pathOverride = null;
      await dir.delete(recursive: true);
    });

    const gstOn = GstConfig(enabled: true);

    Future<int> book(
      int customer,
      List<int> ids, {
      GstConfig gst = gstOn,
      double discount = 0,
      double advance = 0,
      int pickup = 9,
      int ret = 11,
    }) => bookings.create(
      BookingDraft(
        customerId: customer,
        eventDate: day((pickup + ret) ~/ 2),
        pickupDate: day(pickup),
        returnDate: day(ret),
        itemIds: ids,
        discount: discount,
      ),
      isPro: true,
      advance: advance,
      gst: gst,
      now: day(1),
    );

    Future<int> invoice(int bookingId, {String shop = '33', bool gst = true, bool incl = false}) =>
        invoices.createForBooking(
          bookingId,
          shopStateCode: shop,
          prefix: 'RNT',
          gstEnabled: gst,
          taxInclusive: incl,
          now: day(12),
        );

    test('a booking with GST owes rent plus tax', () async {
      final id = await book(local, [dress, tent], advance: 500);
      final b = (await bookings.get(id))!;
      // gown 1000 (18%) + tent 400 x 3 days = 1200 (5%)
      expect(b.rentTotal, 2200);
      expect(b.taxTotal, 180 + 60);
      expect(b.payable, 2440);
      expect(b.balanceDue, 1940);
      expect(b.lines.firstWhere((l) => l.name == 'Gown').gstRate, 18);
      expect(b.lines.firstWhere((l) => l.name == 'Tent').tax, 60);
    });

    test('with GST off the booking is just the rent', () async {
      final id = await book(local, [dress, tent], gst: GstConfig.off);
      final b = (await bookings.get(id))!;
      expect(b.taxTotal, 0);
      expect(b.payable, 2200);
      expect(b.lines.first.gstRate, 0, reason: 'no GST rate is kept when off');
    });

    test('with GST and a discount, tax follows the lower value', () async {
      final id = await book(local, [dress], discount: 100);
      final b = (await bookings.get(id))!;
      expect(b.payable, 1062);
      expect(b.taxTotal, 162);
      expect(b.discount, 100);
    });

    test('rates that include GST do not raise the price', () async {
      final id = await book(local, [dress], gst: const GstConfig(enabled: true, inclusive: true));
      final b = (await bookings.get(id))!;
      expect(b.payable, 1000);
      expect(b.taxTotal, closeTo(152.54, 0.01));
    });

    test('same state: CGST and SGST are equal halves', () async {
      final id = await book(local, [dress, tent]);
      final inv = (await invoices.get(await invoice(id)))!;
      expect(inv.interState, isFalse);
      expect(inv.cgst, 120);
      expect(inv.sgst, 120);
      expect(inv.igst, 0);
      expect(inv.taxable, 2200);
      expect(inv.total, 2440);
      expect(inv.label, 'RNT-0001');
      expect(inv.lines.length, 2);
      expect(inv.lines.firstWhere((l) => l.name == 'Tent').days, 3);
      expect(inv.lines.firstWhere((l) => l.name == 'Gown').days, 1);
      expect(inv.isTaxInvoice, isTrue);
    });

    test('another state, taken from the GSTIN: IGST only', () async {
      final id = await book(faraway, [dress]);
      final inv = (await invoices.get(await invoice(id)))!;
      expect(inv.supplyState, '29');
      expect(inv.interState, isTrue);
      expect(inv.igst, 180);
      expect(inv.cgst + inv.sgst, 0);
      expect(inv.customerGstin, '29ABCDE1234F1Z5');
    });

    test('no customer state: treated as the same state', () async {
      final id = await book(plain, [dress]);
      final inv = (await invoices.get(await invoice(id)))!;
      expect(inv.interState, isFalse);
      expect(inv.cgst, 90);
    });

    test('an odd rupee of tax still adds up', () async {
      final odd = await items.save(RentItem(
        name: 'Odd',
        rate: 101,
        gstRate: 5,
        createdAt: DateTime(2027),
      ));
      final id = await book(local, [odd]);
      final inv = (await invoices.get(await invoice(id)))!;
      expect(inv.cgst + inv.sgst, closeTo(inv.tax, 1e-9));
      expect(inv.taxable + inv.tax, closeTo(inv.total, 0.011));
    });

    test('a plain bill (GST off) has no tax', () async {
      final id = await book(local, [dress], gst: GstConfig.off);
      final inv = (await invoices.get(await invoice(id, gst: false)))!;
      expect(inv.isTaxInvoice, isFalse);
      expect(inv.tax, 0);
      expect(inv.total, 1000);
    });

    test('numbers go up, a booking has one invoice, cancelling allows another', () async {
      final a = await book(local, [dress]);
      final b = await book(local, [tent], pickup: 20, ret: 22);
      final first = await invoice(a);
      final second = await invoice(b);
      expect((await invoices.get(first))!.number, 1);
      expect((await invoices.get(second))!.number, 2);
      try {
        await invoice(a);
        fail('a second invoice for the same booking');
      } on BookingException catch (e) {
        expect(e.error, BookingError.badState);
      }
      await invoices.cancel(first);
      expect((await invoices.forBooking(a)), isNull);
      final again = await invoice(a);
      expect((await invoices.get(again))!.number, 3, reason: 'numbers are never reused');
      expect((await invoices.get(first))!.cancelled, isTrue);
    });

    test('a cancelled booking cannot be invoiced', () async {
      final a = await book(local, [dress]);
      await bookings.cancel(a);
      try {
        await invoice(a);
        fail('should refuse');
      } on BookingException catch (e) {
        expect(e.error, BookingError.badState);
      }
    });

    test('the invoice keeps its numbers when the booking or item changes', () async {
      final a = await book(local, [dress], advance: 300);
      final id = await invoice(a);
      await items.save((await items.get(dress))!.copyWith(rate: 5000, name: 'Renamed'));
      await bookings.update(
        a,
        BookingDraft(
          customerId: local,
          eventDate: day(10),
          pickupDate: day(9),
          returnDate: day(11),
          itemIds: [tent],
        ),
        gst: gstOn,
        now: day(1),
      );
      final inv = (await invoices.get(id))!;
      expect(inv.lines.single.name, 'Gown');
      expect(inv.total, 1180);
      expect(inv.paid, 300);
      expect(inv.due, 880);
    });

    test('list: newest first, search, date range', () async {
      final a = await book(local, [dress]);
      final b = await book(faraway, [tent], pickup: 20, ret: 22);
      await invoices.createForBooking(a, shopStateCode: '33', prefix: 'RNT', gstEnabled: true, taxInclusive: false, now: day(12));
      await invoices.createForBooking(b, shopStateCode: '33', prefix: 'RNT', gstEnabled: true, taxInclusive: false, now: day(14));
      expect((await invoices.list()).map((i) => i.number), [2, 1]);
      expect((await invoices.list(query: 'ravi')).map((i) => i.number), [2]);
      expect((await invoices.list(query: '9000000001')).map((i) => i.number), [1]);
      expect((await invoices.list(query: 'RNT-0002')).map((i) => i.number), [2]);
      expect((await invoices.list(from: day(13), to: day(20))).map((i) => i.number), [2]);
      final cancelled = (await invoices.list()).first;
      await invoices.cancel(cancelled.id);
      expect((await invoices.list(includeCancelled: false)).map((i) => i.number), [1]);
    });

    test('item and customer GST details are saved', () async {
      final it = (await items.get(dress))!;
      expect(it.hsn, '9973');
      expect(it.gstRate, 18);
      final c = (await customers.get(faraway))!;
      expect(c.gstin, '29ABCDE1234F1Z5');
    });

    test('invoice labels', () {
      expect(invoiceLabel('RNT', 7), 'RNT-0007');
      expect(invoiceLabel('', 12), '0012');
    });
  });
}
