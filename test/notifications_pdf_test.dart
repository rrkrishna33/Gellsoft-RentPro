import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/constants.dart';
import 'package:gellsoft_rentpro/data/booking_models.dart';
import 'package:gellsoft_rentpro/data/business_profile.dart';
import 'package:gellsoft_rentpro/data/invoice_models.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/notifications.dart';
import 'package:gellsoft_rentpro/data/photo_store.dart';
import 'package:gellsoft_rentpro/features/invoices/invoice_pdf.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gellsoft_rentpro/subscription/plan.dart';

DateTime day(int d) => DateTime(2027, 3, d);

Booking booking({
  int id = 1,
  BookingStatus status = BookingStatus.booked,
  int pickup = 9,
  int event = 10,
  int ret = 11,
  int remind = 2,
  double payable = 1000,
  bool paidUp = true,
}) => Booking(
  id: id,
  uuid: 'u$id',
  number: id,
  customerId: 1,
  customerName: 'Anu',
  customerPhone: '9876543210',
  eventDate: day(event),
  pickupDate: day(pickup),
  returnDate: day(ret),
  status: status,
  rentTotal: payable,
  depositTotal: 0,
  discount: 0,
  payable: payable,
  notes: '',
  remindDays: remind,
  createdAt: day(1),
  lines: const [
    BookingLine(
      itemId: 1,
      name: 'Gown',
      rateType: RateType.event,
      rate: 1000,
      deposit: 0,
      amount: 1000,
    ),
  ],
  payments: paidUp
      ? [
          Payment(
            id: id,
            bookingId: id,
            kind: PaymentKind.advance,
            amount: payable,
            mode: PayMode.cash,
            note: '',
            paidAt: day(2),
          ),
        ]
      : const [],
);

class _Recorder implements NotificationBackend {
  final calls = <String>[];
  final scheduled = <PlannedNotification>[];
  bool permission = true;

  @override
  Future<void> init() async => calls.add('init');

  @override
  Future<bool> requestPermission() async {
    calls.add('permission');
    return permission;
  }

  @override
  Future<void> cancelAll() async => calls.add('cancelAll');

  @override
  Future<void> schedule(PlannedNotification n) async {
    calls.add('schedule');
    scheduled.add(n);
  }
}

class _Throwing implements NotificationBackend {
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => throw StateError('no prompt here');
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> schedule(PlannedNotification n) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => Lang.current = AppLanguage.en);

  group('notification plan', () {
    final morning = DateTime(2027, 3, 8, 7, 0);

    test('a morning summary for each day that has something to do', () {
      final plan = planNotifications(
        bookings: [booking(pickup: 9, event: 10, ret: 11)],
        settings: const NotifySettings(beforeEvent: false),
        now: morning,
      );
      // sendItems shows on the 8th (2 days before the event), 9th, 10th, 11th
      expect(plan.map((n) => n.at.day), [8, 9, 10, 11]);
      expect(plan.first.at, DateTime(2027, 3, 8, 8, 0));
      expect(plan.first.title, '1 things need you today');
      expect(plan.first.body, '1 to send');
    });

    test('a time that has passed today is not scheduled', () {
      final plan = planNotifications(
        bookings: [booking()],
        settings: const NotifySettings(beforeEvent: false),
        now: DateTime(2027, 3, 8, 9, 30),
      );
      expect(plan.first.at.day, 9);
    });

    test('the reminder time follows the setting', () {
      final plan = planNotifications(
        bookings: [booking()],
        settings: const NotifySettings(
          beforeEvent: false,
          hour: 18,
          minute: 30,
        ),
        now: morning,
      );
      expect(plan.first.at, DateTime(2027, 3, 8, 18, 30));
    });

    test('each booking gets a reminder before the event and on return day', () {
      final plan = planNotifications(
        bookings: [booking(id: 7, pickup: 12, event: 13, ret: 14, remind: 3)],
        settings: const NotifySettings(daily: false),
        now: morning,
      );
      expect(plan.length, 2);
      final send = plan.firstWhere((n) => n.title.startsWith('Send the items'));
      expect(send.at, DateTime(2027, 3, 10, 8, 0), reason: '3 days before the 13th');
      expect(send.title, 'Send the items for #7');
      expect(send.body, 'Gown for Anu, event on 13 Mar 2027');
      final back = plan.firstWhere((n) => n.title.startsWith('Items due back'));
      expect(back.at, DateTime(2027, 3, 14, 8, 0));
      expect(send.id, isNot(back.id));
    });

    test('money still due is counted in the morning summary', () {
      final plan = planNotifications(
        bookings: [booking(paidUp: false)],
        settings: const NotifySettings(beforeEvent: false),
        now: morning,
      );
      expect(plan.first.body, contains('1 to send'));
      expect(plan.first.body, contains('1 with money due'));
    });

    test('out bookings only remind about the return', () {
      final plan = planNotifications(
        bookings: [booking(status: BookingStatus.pickedUp, ret: 12)],
        settings: const NotifySettings(daily: false),
        now: morning,
      );
      expect(plan.single.title, startsWith('Items due back'));
    });

    test('cancelled and returned bookings give nothing', () {
      final plan = planNotifications(
        bookings: [
          booking(id: 1, status: BookingStatus.cancelled),
          booking(id: 2, status: BookingStatus.returned),
        ],
        settings: const NotifySettings(),
        now: morning,
      );
      expect(plan, isEmpty);
    });

    test('both switches off plans nothing; the list is sorted and capped', () {
      expect(
        planNotifications(
          bookings: [booking()],
          settings: const NotifySettings(daily: false, beforeEvent: false),
          now: morning,
        ),
        isEmpty,
      );
      final many = [
        for (var i = 1; i <= 40; i++)
          booking(id: i, pickup: 9 + i % 3, event: 10 + i % 3, ret: 11 + i % 3),
      ];
      final plan = planNotifications(
        bookings: many,
        settings: const NotifySettings(),
        now: morning,
      );
      expect(plan.length, notifyLimit);
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i].at.isBefore(plan[i - 1].at), isFalse);
      }
      expect(plan.map((n) => n.id).toSet().length, plan.length, reason: 'unique ids');
    });

    test('Tamil titles when the app is in Tamil', () {
      Lang.current = AppLanguage.ta;
      final plan = planNotifications(
        bookings: [booking()],
        settings: const NotifySettings(beforeEvent: false),
        now: morning,
      );
      expect(plan.first.title, contains('இன்று'));
    });
  });

  group('syncing with the phone', () {
    late _Recorder phone;
    setUp(() {
      phone = _Recorder();
      NotificationService.backend = phone;
    });

    test('Pro: old reminders are cleared and the plan is scheduled', () async {
      final n = await NotificationService.sync(
        isPro: true,
        settings: const NotifySettings(),
        bookings: [booking()],
        now: DateTime(2027, 3, 8, 7),
      );
      expect(n, greaterThan(0));
      expect(phone.calls.first, 'cancelAll');
      expect(phone.scheduled.length, n);
    });

    test('without Pro nothing stays scheduled', () async {
      final n = await NotificationService.sync(
        isPro: false,
        settings: const NotifySettings(),
        bookings: [booking()],
        now: DateTime(2027, 3, 8, 7),
      );
      expect(n, 0);
      expect(phone.calls, ['cancelAll']);
    });

    test('both switches off schedules nothing', () async {
      final n = await NotificationService.sync(
        isPro: true,
        settings: const NotifySettings(daily: false, beforeEvent: false),
        bookings: [booking()],
        now: DateTime(2027, 3, 8, 7),
      );
      expect(n, 0);
      expect(phone.scheduled, isEmpty);
    });

    test('asking permission goes to the phone', () async {
      expect(await NotificationService.askPermission(), isTrue);
      phone.permission = false;
      expect(await NotificationService.askPermission(), isFalse);
    });
  });

  group('reminders for several shops', () {
    late _Recorder phone;
    setUp(() {
      phone = _Recorder();
      NotificationService.backend = phone;
    });

    final now = DateTime(2027, 3, 8, 7);

    test('every shop gets its reminders, and each title says which shop', () async {
      await NotificationService.sync(
        isPro: true,
        settings: const NotifySettings(daily: false),
        bookings: [booking(id: 1)],
        shopName: 'Royal Costumes',
        others: [
          ShopReminders(name: 'Glow Studio', service: true, bookings: [booking(id: 1)]),
        ],
        now: now,
      );
      final titles = phone.scheduled.map((n) => n.title).toList();
      expect(titles.where((t) => t.startsWith('Royal Costumes: ')), isNotEmpty);
      expect(titles.where((t) => t.startsWith('Glow Studio: ')), isNotEmpty);
      // two shops can both have a booking with id 1: the notifications must
      // not replace each other
      final ids = phone.scheduled.map((n) => n.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'every notification has its own id');
    });

    test('with one shop the titles are as they were', () async {
      await NotificationService.sync(
        isPro: true,
        settings: const NotifySettings(daily: false),
        bookings: [booking()],
        shopName: 'Royal Costumes',
        now: now,
      );
      expect(phone.scheduled.map((n) => n.title), contains('Send the items for #1'));
      expect(phone.scheduled.any((n) => n.title.contains('Royal Costumes')), isFalse);
    });

    test('they are in time order across shops, and the cap holds for all', () async {
      final many = [for (var i = 1; i <= 40; i++) booking(id: i, pickup: 9, event: 10, ret: 11)];
      final n = await NotificationService.sync(
        isPro: true,
        settings: const NotifySettings(),
        bookings: many,
        shopName: 'A',
        others: [ShopReminders(name: 'B', service: false, bookings: many)],
        now: now,
      );
      expect(n, notifyLimit);
      final times = phone.scheduled.map((n) => n.at).toList();
      final sorted = [...times]..sort();
      expect(times, sorted);
    });

    Booking made({
      required String name,
      int qty = 1,
      String time = '',
      required double rate,
    }) => Booking(
      id: 7,
      uuid: 'u7',
      number: 7,
      customerId: 1,
      customerName: 'Anu',
      customerPhone: '9876543210',
      eventDate: day(10),
      pickupDate: day(10),
      returnDate: day(10),
      status: BookingStatus.booked,
      rentTotal: rate * qty,
      depositTotal: 0,
      discount: 0,
      notes: '',
      remindDays: 1,
      eventTime: time,
      createdAt: day(1),
      lines: [
        BookingLine(
          itemId: 1,
          name: name,
          qty: qty,
          rateType: RateType.event,
          rate: rate,
          deposit: 0,
          amount: rate * qty,
        ),
      ],
    );

    test('an appointment is worded as one, with its time, and has no return reminder', () {
      final plan = planNotifications(
        bookings: [made(name: 'Bridal makeup', rate: 15000, time: '09:30')],
        settings: const NotifySettings(daily: false),
        now: now,
        service: true,
      );
      expect(plan.length, 1, reason: 'no "due back" reminder for a service');
      expect(plan.single.title, 'Appointment coming up: #7');
      expect(plan.single.body, contains('Bridal makeup'));
      expect(plan.single.body, contains('09:30 AM'));
    });

    test('pieces are named in the reminder', () {
      final plan = planNotifications(
        bookings: [made(name: 'Chair', qty: 10, rate: 50)],
        settings: const NotifySettings(daily: false),
        now: now,
      );
      expect(plan.first.body, contains('Chair × 10'));
    });
  });

  group('several reminder times a day', () {
    final morning = DateTime(2027, 3, 8, 6, 0);

    test('times are sorted, never repeated, and at most four', () {
      const a = NotifySettings(hour: 18, minute: 30, extraTimes: [480, 480, 720]);
      expect(a.times, [480, 720, 1110]);
      expect([for (final t in a.timesOfDay) t.hour], [8, 12, 18]);
      const many = NotifySettings(extraTimes: [600, 700, 800, 900, 1000]);
      expect(many.times.length, NotifySettings.maxTimes);
      // setting the times from a list keeps the earliest as the main one
      final b = const NotifySettings().withTimes([1200, 480, 960]);
      expect(b.hour, 8);
      expect(b.minute, 0);
      expect(b.extraTimes, [960, 1200]);
      expect(const NotifySettings().withTimes(const []).times, [480],
          reason: 'there is always at least one time');
    });

    test('the morning summary is set for every time of day', () {
      final plan = planNotifications(
        bookings: [booking()],
        settings: const NotifySettings(
          beforeEvent: false,
          extraTimes: [18 * 60],
        ),
        now: morning,
      );
      // 8th to 11th has something to do on four days, twice a day
      final byDay = <int, List<DateTime>>{};
      for (final n in plan) {
        byDay.putIfAbsent(n.at.day, () => []).add(n.at);
      }
      expect(byDay[9], isNotNull);
      for (final times in byDay.values) {
        expect(times.map((t) => t.hour), [8, 18]);
      }
      final ids = plan.map((n) => n.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'each has its own id');
    });

    test('each booking reminder is repeated at every time too', () {
      final plan = planNotifications(
        bookings: [booking()],
        settings: const NotifySettings(
          daily: false,
          extraTimes: [13 * 60, 20 * 60],
        ),
        now: morning,
      );
      final send = plan.where((n) => n.title.startsWith('Send the items')).toList();
      final back = plan.where((n) => n.title.startsWith('Items due back')).toList();
      expect(send.map((n) => n.at.hour), [8, 13, 20]);
      expect(send.every((n) => n.at.day == 8), isTrue, reason: 'two days before the 10th');
      expect(back.map((n) => n.at.hour), [8, 13, 20]);
      final ids = plan.map((n) => n.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('a time that has already passed today is not scheduled', () {
      final plan = planNotifications(
        bookings: [booking()],
        settings: const NotifySettings(
          daily: false,
          extraTimes: [18 * 60],
        ),
        now: DateTime(2027, 3, 8, 12, 0), // after 8, before 18
      );
      final send = plan.where((n) => n.title.startsWith('Send the items')).toList();
      expect(send.map((n) => n.at.hour), [18]);
    });

    test('with one time nothing changes', () {
      final one = planNotifications(
        bookings: [booking()],
        settings: const NotifySettings(),
        now: morning,
      );
      final same = planNotifications(
        bookings: [booking()],
        settings: const NotifySettings(extraTimes: []),
        now: morning,
      );
      expect(one.map((n) => (n.id, n.at)), same.map((n) => (n.id, n.at)));
    });

    test('the times are saved and read back; damaged values are dropped', () async {
      SharedPreferences.setMockInitialValues({});
      await const NotifySettings(
        hour: 7,
        minute: 5,
        extraTimes: [13 * 60, 20 * 60 + 30],
      ).save();
      final back = await NotifySettings.load();
      expect(back.times, [7 * 60 + 5, 13 * 60, 20 * 60 + 30]);
      SharedPreferences.setMockInitialValues({
        'n_hour': 9,
        'n_extra': ['600', 'abc', '-5', '99999', '1020'],
      });
      expect((await NotifySettings.load()).times, [540, 600, 1020]);
      // a phone from before several times had none saved
      SharedPreferences.setMockInitialValues({'n_hour': 6, 'n_minute': 30});
      expect((await NotifySettings.load()).times, [390]);
    });
  });

  group('asking for notifications on the first open', () {
    late _Recorder phone;
    setUp(() {
      phone = _Recorder();
      NotificationService.backend = phone;
    });

    test('asks the first time, and only the first time', () async {
      SharedPreferences.setMockInitialValues({});
      await askNotificationPermissionOnFirstOpen();
      expect(phone.calls.where((c) => c == 'permission'), hasLength(1));
      await askNotificationPermissionOnFirstOpen();
      await askNotificationPermissionOnFirstOpen();
      expect(phone.calls.where((c) => c == 'permission'), hasLength(1));
    });

    test('a person who said no is not asked at every start', () async {
      SharedPreferences.setMockInitialValues({});
      phone.permission = false;
      await askNotificationPermissionOnFirstOpen();
      await askNotificationPermissionOnFirstOpen();
      expect(phone.calls.where((c) => c == 'permission'), hasLength(1));
    });

    test('a phone that cannot show the prompt never breaks the app', () async {
      SharedPreferences.setMockInitialValues({});
      NotificationService.backend = _Throwing();
      await askNotificationPermissionOnFirstOpen(); // must not throw
      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool('s_notifask'), isTrue, reason: 'not asked again next time');
    });
  });

  group('settings are kept', () {
    test('defaults, save and load', () async {
      const a = NotifySettings();
      expect(a.daily, isTrue);
      expect(a.hour, 8);
      final b = a.copyWith(daily: false, hour: 17, minute: 15);
      expect(b.daily, isFalse);
      expect(b.beforeEvent, isTrue);
      expect(b.time.hour, 17);
      expect(b.time.minute, 15);
    });
  });

  group('PDFs', () {
    const shop = BusinessProfile(
      name: 'Royal Costumes',
      type: ShopType.costume,
      phone: '9000000000',
      address: 'Madurai',
      gstEnabled: true,
      gstin: '33ABCDE1234F1Z5',
      invoiceFooter: 'Thank you',
    );

    Invoice inv({bool gst = true, bool inter = false, bool cancelled = false, String name = 'Anu'}) => Invoice(
      id: 1,
      uuid: 'x',
      bookingId: 1,
      prefix: 'RNT',
      number: 12,
      date: day(12),
      cancelled: cancelled,
      customerName: name,
      customerPhone: '9876543210',
      customerAddress: 'Sivakasi',
      customerGstin: gst ? '29ABCDE1234F1Z5' : '',
      supplyState: gst ? '29' : '',
      interState: inter,
      gstEnabled: gst,
      taxInclusive: false,
      discount: 50,
      taxable: 950,
      cgst: inter ? 0 : 85.5,
      sgst: inter ? 0 : 85.5,
      igst: inter ? 171 : 0,
      total: 1121,
      eventDate: day(10),
      pickupDate: day(9),
      returnDate: day(11),
      paid: 500,
      bookingNumber: 3,
      lines: [
        InvoiceLine(
          name: 'Gown',
          hsn: '9973',
          rateType: RateType.event,
          rate: 1000,
          days: 1,
          gstRate: 18,
          taxable: 950,
          cgst: inter ? 0 : 85.5,
          sgst: inter ? 0 : 85.5,
          igst: inter ? 171 : 0,
          total: 1121,
        ),
      ],
    );

    Payment pay(PaymentKind k) => Payment(
      id: 5,
      bookingId: 1,
      kind: k,
      amount: 500,
      mode: PayMode.upi,
      note: 'first',
      paidAt: day(3),
    );

    test('an invoice is a real PDF', () async {
      final bytes = await buildInvoicePdf(
        shop: shop,
        invoice: inv(),
        payments: [pay(PaymentKind.advance)],
        depositTotal: 2000,
        depositHeld: 1500,
      );
      expect(bytes.length, greaterThan(1500));
      expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    });

    test('plain bills, IGST invoices and cancelled ones all build', () async {
      for (final i in [inv(gst: false), inv(inter: true), inv(cancelled: true)]) {
        final bytes = await buildInvoicePdf(shop: shop, invoice: i);
        expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
      }
    });

    test('Tamil names do not break the PDF', () async {
      final bytes = await buildInvoicePdf(
        shop: shop.copyWith(name: 'ராயல் ஆடைகள்'),
        invoice: inv(name: 'அனு'),
      );
      expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    });

    // a one-pixel PNG: a real image the PDF can embed
    final tinyPng = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGM4scAGiBggFAAwLgaRMe177wAAAABJRU5ErkJggg==',
    );

    test('the shop logo goes on the invoice and the receipt', () async {
      final dir = Directory.systemTemp.createTempSync('rentpro_logo');
      addTearDown(() {
        PhotoStore.folderOverride = null;
        dir.deleteSync(recursive: true);
      });
      PhotoStore.folderOverride = dir;
      File('${dir.path}/aaaaaaaa-0001.png').writeAsBytesSync(tinyPng);
      final withLogo = shop.copyWith(logoName: 'aaaaaaaa-0001.png');
      final plain = await buildInvoicePdf(shop: shop, invoice: inv());
      final logoPdf = await buildInvoicePdf(shop: withLogo, invoice: inv());
      expect(latin1.decode(logoPdf.sublist(0, 5)), '%PDF-');
      expect(logoPdf.length, isNot(plain.length), reason: 'the picture is in the file');
      final receipt = await buildReceiptPdf(
        shop: withLogo,
        booking: booking(),
        payment: pay(PaymentKind.advance),
      );
      expect(latin1.decode(receipt.sublist(0, 5)), '%PDF-');
    });

    test('a logo that is not a picture does not stop the invoice or receipt', () async {
      final dir = Directory.systemTemp.createTempSync('rentpro_badlogo');
      addTearDown(() {
        PhotoStore.folderOverride = null;
        dir.deleteSync(recursive: true);
      });
      PhotoStore.folderOverride = dir;
      File('${dir.path}/eeeeeeee-0005.png').writeAsBytesSync([1, 2, 3, 4, 5, 6]);
      final broken = shop.copyWith(logoName: 'eeeeeeee-0005.png');
      final inv1 = await buildInvoicePdf(shop: broken, invoice: inv());
      expect(latin1.decode(inv1.sublist(0, 5)), '%PDF-');
      final rec = await buildReceiptPdf(
        shop: broken,
        booking: booking(),
        payment: pay(PaymentKind.advance),
      );
      expect(latin1.decode(rec.sublist(0, 5)), '%PDF-');
    });

    test('a logo that is gone does not stop the invoice', () async {
      final dir = Directory.systemTemp.createTempSync('rentpro_nologo');
      addTearDown(() {
        PhotoStore.folderOverride = null;
        dir.deleteSync(recursive: true);
      });
      PhotoStore.folderOverride = dir;
      final bytes = await buildInvoicePdf(
        shop: shop.copyWith(logoName: 'dddddddd-0004.png'),
        invoice: inv(),
      );
      expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    });

    test('pieces and services build, with and without GST', () async {
      Invoice withQty({required bool gst}) => Invoice(
        id: 2,
        uuid: 'y',
        bookingId: 2,
        prefix: 'RNT',
        number: 13,
        date: day(12),
        cancelled: false,
        customerName: 'Anu',
        customerPhone: '9876543210',
        customerAddress: '',
        customerGstin: '',
        supplyState: gst ? '33' : '',
        interState: false,
        gstEnabled: gst,
        taxInclusive: false,
        discount: 0,
        taxable: 500,
        cgst: gst ? 45 : 0,
        sgst: gst ? 45 : 0,
        igst: 0,
        total: gst ? 590 : 500,
        eventDate: day(10),
        pickupDate: day(9),
        returnDate: day(11),
        paid: 0,
        bookingNumber: 4,
        lines: [
          InvoiceLine(
            name: 'Chair',
            hsn: '9973',
            rateType: RateType.event,
            rate: 50,
            days: 1,
            qty: 10,
            gstRate: gst ? 18 : 0,
            taxable: 500,
            cgst: gst ? 45 : 0,
            sgst: gst ? 45 : 0,
            igst: 0,
            total: gst ? 590 : 500,
          ),
        ],
      );
      for (final gst in [true, false]) {
        final rental = await buildInvoicePdf(shop: shop, invoice: withQty(gst: gst));
        expect(latin1.decode(rental.sublist(0, 5)), '%PDF-');
        // a makeup artist's bill: services, an appointment time, no days
        final service = await buildInvoicePdf(
          shop: shop.copyWith(type: ShopType.makeup),
          invoice: withQty(gst: gst),
          eventTime: '14:30',
        );
        expect(latin1.decode(service.sublist(0, 5)), '%PDF-');
        expect(service.length, isNot(rental.length));
      }
    });

    test('a receipt and a refund voucher build', () async {
      final b = booking();
      for (final k in [PaymentKind.advance, PaymentKind.refund]) {
        final bytes = await buildReceiptPdf(shop: shop, booking: b, payment: pay(k));
        expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
        expect(bytes.length, greaterThan(1000));
      }
    });
  });

  group('plan', () {
    test('free limit states', () {
      const free = Entitlement(tier: Tier.free, enforced: true);
      expect(free.bookingState(0), BookingState.ok);
      expect(free.bookingState(warnAtBookings), BookingState.nearLimit);
      expect(free.bookingState(FreePlan.bookingsPerMonth), BookingState.blocked);
      expect(free.allows(ProFeature.notifications), isFalse);
      const pro = Entitlement(tier: Tier.pro, enforced: true);
      expect(pro.bookingState(99), BookingState.ok);
      expect(pro.allows(ProFeature.unlimitedPhotos), isTrue);
      const launch = Entitlement(tier: Tier.free);
      expect(launch.unlocked, isTrue, reason: 'nothing locked before the paywall');
    });

    test('trial then free, and Pro from a subscription', () {
      final start = DateTime(2027, 3, 1);
      final onTrial = Entitlement.derive(now: DateTime(2027, 3, 3), trialStart: start, enforced: true);
      expect(onTrial.tier, Tier.trial);
      expect(onTrial.trialDaysLeft(DateTime(2027, 3, 3)), 5);
      final after = Entitlement.derive(now: DateTime(2027, 3, 9), trialStart: start, enforced: true);
      expect(after.tier, Tier.free);
      final paid = Entitlement.derive(
        now: DateTime(2027, 3, 9),
        trialStart: start,
        proUntil: DateTime(2027, 4, 9),
        enforced: true,
      );
      expect(paid.tier, Tier.pro);
    });

    test('the clock cannot be moved back to cheat', () {
      final seen = DateTime(2027, 3, 10, 12);
      expect(TimeGuard.effective(DateTime(2027, 3, 1), seen), seen);
      expect(TimeGuard.effective(DateTime(2027, 3, 10, 11, 58), seen), DateTime(2027, 3, 10, 11, 58));
      expect(TimeGuard.effective(DateTime(2027, 3, 11), seen), DateTime(2027, 3, 11));
    });
  });
}
