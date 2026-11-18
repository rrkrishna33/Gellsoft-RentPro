import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/constants.dart';
import 'package:gellsoft_rentpro/core/terms.dart';
import 'package:gellsoft_rentpro/data/booking_models.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/invoice_repo.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/report_repo.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DateTime day(int d) => DateTime(2027, 3, d);
DateRange march() => (from: DateTime(2027, 3), to: DateTime(2027, 4));

void main() {
  late Directory dir;
  final bookings = BookingRepo();
  final items = ItemRepo();
  final customers = CustomerRepo();
  late int anu;
  late int bike; // 400 a day, deposit 2000
  late int helmet; // 100 an event

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rentpro_edit_rent');
    AppDatabase.pathOverride = '${dir.path}/test.db';
    anu = await customers.save(
      Customer(name: 'Anu', phone: '9000000001', createdAt: DateTime(2027)),
    );
    bike = await items.save(
      RentItem(
        name: 'Bike',
        rate: 400,
        rateType: RateType.day,
        deposit: 2000,
        createdAt: DateTime(2027),
      ),
    );
    helmet = await items.save(
      RentItem(name: 'Helmet', rate: 100, createdAt: DateTime(2027)),
    );
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AppDatabase.pathOverride = null;
    await dir.delete(recursive: true);
  });

  BookingDraft draft({
    Map<int, double> rates = const {},
    Map<int, double> deposits = const {},
    double discount = 0,
    int pickup = 10,
    int ret = 11,
  }) => BookingDraft(
    customerId: anu,
    eventDate: day(pickup),
    pickupDate: day(pickup),
    returnDate: day(ret),
    itemIds: [bike, helmet],
    rates: rates,
    deposits: deposits,
    discount: discount,
  );

  Future<int> invoiceFor(int id) => InvoiceRepo().createForBooking(
    id,
    shopStateCode: '33',
    prefix: 'RP',
    gstEnabled: false,
    taxInclusive: false,
    now: day(12),
  );

  group('a rent agreed for one booking', () {
    test('without a change the item rates are used', () async {
      final id = await bookings.create(draft(), isPro: true, now: day(1));
      final b = (await bookings.get(id))!;
      expect(b.rentTotal, 400 * 2 + 100);
      expect(b.depositTotal, 2000);
    });

    test('the agreed rent and deposit replace the item rate on the booking',
        () async {
      final id = await bookings.create(
        draft(rates: {bike: 350, helmet: 0}, deposits: {bike: 1000}),
        isPro: true,
        now: day(1),
      );
      final b = (await bookings.get(id))!;
      final bikeLine = b.lines.firstWhere((l) => l.name == 'Bike');
      expect(bikeLine.rate, 350);
      expect(bikeLine.amount, 700); // two days
      expect(bikeLine.deposit, 1000);
      expect(b.lines.firstWhere((l) => l.name == 'Helmet').amount, 0);
      expect(b.rentTotal, 700);
      expect(b.payable, 700);
      expect(b.depositTotal, 1000);
      // the item's own rate is not touched
      expect((await items.get(bike))!.rate, 400);
    });

    test('a negative rent is refused', () async {
      expect(
        () => bookings.create(draft(rates: {bike: -5}), isPro: true, now: day(1)),
        throwsA(
          isA<BookingException>().having(
            (e) => e.error,
            'error',
            BookingError.badAmount,
          ),
        ),
      );
    });

    test('invoice and reports show the agreed rent', () async {
      final id = await bookings.create(
        draft(rates: {bike: 350}),
        isPro: true,
        now: day(1),
      );
      final inv = (await InvoiceRepo().get(await invoiceFor(id)))!;
      final line = inv.lines.firstWhere((l) => l.name == 'Bike');
      expect(line.rate, 350);
      expect(line.total, 700);
      expect(inv.total, 800); // 700 + the helmet's 100

      final s = await ReportRepo().summary(march());
      expect(s.billed, 800);
      expect(s.outstanding, 800);
    });

    test('changing the rent of a booking that has an invoice updates the invoice',
        () async {
      final id = await bookings.create(draft(), isPro: true, now: day(1));
      final invId = await invoiceFor(id);
      expect((await InvoiceRepo().get(invId))!.total, 900);
      await bookings.addPayment(
        id,
        kind: PaymentKind.advance,
        amount: 300,
        mode: PayMode.cash,
        at: day(2),
      );

      // the shop agrees 300 a day and a discount
      await bookings.update(
        id,
        draft(rates: {bike: 300, helmet: 100}, discount: 50),
        now: day(3),
      );
      await InvoiceRepo().refreshForBooking(id);

      final b = (await bookings.get(id))!;
      expect(b.payable, 650); // 600 + 100 - 50
      final inv = (await InvoiceRepo().get(invId))!;
      expect(inv.total, 650);
      expect(inv.discount, 50);
      expect(inv.number, 1, reason: 'the invoice keeps its number');
      expect(inv.lines.firstWhere((l) => l.name == 'Bike').rate, 300);
      expect((await ReportRepo().summary(march())).billed, 650);
      // what was already paid is untouched
      expect(b.rentPaid, 300);
      expect(b.balanceDue, 350);
    });

    test('editing a booking keeps its agreed rent, not today\'s item rate',
        () async {
      final id = await bookings.create(
        draft(rates: {bike: 350}),
        isPro: true,
        now: day(1),
      );
      // the shop raises the bike's own rate later
      await items.save((await items.get(bike))!.copyWith(rate: 600));
      final b = (await bookings.get(id))!;
      // the form sends the agreed rates back as they were
      await bookings.update(
        id,
        draft(
          rates: {for (final l in b.lines) l.itemId: l.rate},
          deposits: {for (final l in b.lines) l.itemId: l.deposit},
        ),
        now: day(3),
      );
      expect(
        (await bookings.get(id))!.lines.firstWhere((l) => l.name == 'Bike').rate,
        350,
      );
    });

    test('a cancelled invoice is left alone', () async {
      final id = await bookings.create(draft(), isPro: true, now: day(1));
      final invId = await invoiceFor(id);
      await InvoiceRepo().cancel(invId);
      await bookings.update(id, draft(rates: {bike: 100}), now: day(3));
      await InvoiceRepo().refreshForBooking(id);
      expect((await InvoiceRepo().get(invId))!.total, 900);
    });
  });

  group('wording follows the kind of shop', () {
    test('a bike rental shop speaks of vehicles and has no event', () {
      Lang.current = AppLanguage.en;
      const bikes = Terms(ShopType.vehicle);
      expect(bikes.items, 'Vehicles');
      expect(bikes.addItem, 'Add vehicle');
      expect(bikes.rentLabel, 'Rent for one vehicle (₹)');
      expect(bikes.depositLabel, 'Deposit for one vehicle (₹)');
      expect(bikes.quantityHelp, 'Vehicles you have');
      expect(bikes.remindLabel, 'Remind me before pickup');
      expect(bikes.hasEvent, isFalse);
      expect(bikes.rateTypes, [RateType.day, RateType.hour]);
      expect(bikes.defaultRateType, RateType.day);
    });

    test('equipment shops speak of equipment and units, charged by the day',
        () {
      Lang.current = AppLanguage.en;
      const tools = Terms(ShopType.equipment);
      expect(tools.items, 'Equipment');
      expect(tools.item, 'Equipment item');
      expect(tools.addItem, 'Add equipment');
      expect(tools.rentLabel, 'Rent for one unit (₹)');
      expect(tools.depositLabel, 'Deposit for one unit (₹)');
      expect(tools.quantityHelp, 'Units you have');
      expect(tools.sizeLabel, 'Model or capacity (optional)');
      expect(tools.defaultRateType, RateType.day);
      expect(tools.hasEvent, isTrue);
      expect(tools.rateTypes, RateType.values);
    });

    test('vehicle shops ask for a model or registration, not a size', () {
      expect(
        const Terms(ShopType.vehicle).sizeLabel,
        'Model or registration no. (optional)',
      );
    });

    test('costume, decor and other shops keep the usual words and the event day',
        () {
      for (final t in [ShopType.costume, ShopType.decor, ShopType.other]) {
        final terms = Terms(t);
        expect(terms.items, 'Items');
        expect(terms.item, 'Item');
        expect(terms.rentLabel, 'Rent for one piece (₹)');
        expect(terms.sizeLabel, 'Size (optional)');
        expect(terms.hasEvent, isTrue);
        expect(terms.rateTypes, RateType.values);
        expect(terms.defaultRateType, RateType.event);
      }
      expect(const Terms(ShopType.makeup).items, 'Services');
      expect(const Terms(ShopType.makeup).item, 'Service');
    });
  });
}
