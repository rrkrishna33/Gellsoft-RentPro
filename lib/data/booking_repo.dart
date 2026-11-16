import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../core/booking_math.dart';
import '../core/format.dart';
import '../core/ids.dart';
import '../subscription/plan.dart';
import 'booking_models.dart';
import 'database.dart';
import 'models.dart';
import 'reminders.dart';
import 'shops.dart';

/// Why a booking could not be saved or changed.
enum BookingError {
  /// The free plan's bookings for this month are used up.
  limitReached,

  /// An item is already booked for some of these days.
  itemBusy,

  /// An item has some free pieces on these days, but not as many as wanted.
  notEnough,

  /// Pickup, event and return are not in order.
  badDates,

  /// No items were chosen.
  noItems,

  /// An item cannot be booked (in repair, retired or removed).
  itemUnavailable,

  /// The booking is not in a state that allows this.
  badState,

  /// The amount is not allowed (zero, or more than is due).
  badAmount,

  /// The discount is more than the rent.
  badDiscount,
}

class BookingException implements Exception {
  const BookingException(this.error, [this.detail = '']);
  final BookingError error;

  /// For [BookingError.itemBusy] and [BookingError.itemUnavailable]: the item.
  final String detail;

  @override
  String toString() => 'BookingException($error, $detail)';
}

/// What a person fills in to make or change a booking.
class BookingDraft {
  final int customerId;
  final DateTime eventDate;
  final DateTime pickupDate;
  final DateTime returnDate;
  final List<int> itemIds;

  /// How many of each item (item id -> pieces). An item not listed is one.
  final Map<int, int> quantities;
  final double discount;
  final String notes;
  final int remindDays;

  /// The appointment time ("14:30") of a service booking, or ''.
  final String eventTime;

  /// Who is making the booking, or '' when staff logins are off.
  final String createdBy;

  const BookingDraft({
    required this.customerId,
    required this.eventDate,
    required this.pickupDate,
    required this.returnDate,
    required this.itemIds,
    this.quantities = const {},
    this.discount = 0,
    this.notes = '',
    this.remindDays = 2,
    this.eventTime = '',
    this.createdBy = '',
  });

  int qtyOf(int itemId) {
    final q = quantities[itemId] ?? 1;
    return q < 1 ? 1 : q;
  }
}

/// An item that does not have enough free pieces for the days asked about.
class ItemConflict {
  final int itemId;
  final int bookingId;
  final int bookingNumber;
  final String customerName;
  final DateTime pickupDate;
  final DateTime returnDate;

  /// How many pieces the shop has, and how many of them are free on every
  /// one of the days asked about.
  final int stock;
  final int free;

  const ItemConflict({
    required this.itemId,
    required this.bookingId,
    required this.bookingNumber,
    required this.customerName,
    required this.pickupDate,
    required this.returnDate,
    this.stock = 1,
    this.free = 0,
  });
}

/// How many pieces of an item are free for some days, and who has the rest.
class ItemAvailability {
  const ItemAvailability({
    required this.itemId,
    required this.stock,
    required this.free,
    this.holder,
  });
  final int itemId;
  final int stock;

  /// Free on every one of the days (never negative).
  final int free;

  /// A booking that has some of the pieces on those days, if any.
  final ItemConflict? holder;
}

/// Which bookings the list shows.
enum BookingFilter {
  upcoming('Upcoming'),
  out('Out'),
  returned('Returned'),
  due('Balance due'),
  cancelled('Cancelled');

  final String en;
  const BookingFilter(this.en);

  /// The statuses this list shows. Out covers items collected by the
  /// customer and items sent by courier. Balance due has no status of its
  /// own: it is every booking, not cancelled, that still owes rent.
  List<BookingStatus> get statuses => switch (this) {
    upcoming => [BookingStatus.booked],
    out => [BookingStatus.pickedUp, BookingStatus.dispatched],
    returned => [BookingStatus.returned],
    due => [
      BookingStatus.booked,
      BookingStatus.pickedUp,
      BookingStatus.dispatched,
      BookingStatus.returned,
    ],
    cancelled => [BookingStatus.cancelled],
  };
}

class _Prepared {
  const _Prepared({
    required this.lines,
    required this.rent,
    required this.deposit,
    required this.tax,
    required this.payable,
  });
  final List<Map<String, Object?>> lines;
  final double rent;
  final double deposit;
  final double tax;
  final double payable;
}

class BookingRepo {
  /// Bookings with the given [filter], newest work first. [query] matches the
  /// customer's name or phone, or the booking number.
  Future<List<Booking>> list({
    BookingFilter filter = BookingFilter.upcoming,
    String query = '',
  }) async {
    final d = await AppDatabase.instance.db;
    final statuses = filter.statuses;
    final where = StringBuffer(
      'b.deleted = 0 AND b.status IN (${List.filled(statuses.length, '?').join(',')})',
    );
    final args = <Object?>[for (final s in statuses) s.db];
    if (filter == BookingFilter.due) {
      where.write(
        ' AND b.payable - COALESCE((SELECT SUM(p.amount) FROM payments p'
        " WHERE p.booking_id = b.id AND p.kind IN ('advance', 'balance')), 0)"
        ' > 0.005',
      );
    }
    final q = query.trim();
    if (q.isNotEmpty) {
      final like =
          '%${q.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      where.write(
        " AND (c.name LIKE ? ESCAPE '\\' OR c.phone LIKE ? ESCAPE '\\'"
        " OR CAST(b.number AS TEXT) = ?)",
      );
      args.addAll([like, like, q.replaceFirst('#', '')]);
    }
    final upward =
        filter == BookingFilter.upcoming ||
        filter == BookingFilter.out ||
        filter == BookingFilter.due;
    final rows = await d.rawQuery('''
      SELECT b.*, c.name AS c_name, c.phone AS c_phone
      FROM bookings b JOIN customers c ON c.id = b.customer_id
      WHERE $where
      ORDER BY b.pickup_date ${upward ? 'ASC' : 'DESC'}, b.id DESC
    ''', args);
    return _hydrate(d, rows);
  }

  /// The bookings the reminders look at: everything booked or out, plus
  /// returned bookings that still have rent to collect.
  Future<List<Booking>> forReminders() async {
    final d = await AppDatabase.instance.db;
    return _remindersIn(d);
  }

  /// The same for any shop on the phone, so reminders cover every shop, not
  /// only the one that is open. A shop that is not open is read on a
  /// connection of its own; one with no data yet has none.
  Future<List<Booking>> forRemindersOf(String shopId) async {
    if (shopId == Shops.activeId) return forReminders();
    final path = await AppDatabase.instance.pathFor(shopId);
    if (!File(path).existsSync()) return const [];
    final db = await openDatabase(path, readOnly: true, singleInstance: false);
    try {
      return await _remindersIn(db);
    } finally {
      await db.close();
    }
  }

  Future<List<Booking>> _remindersIn(DatabaseExecutor d) async {
    final rows = await d.rawQuery('''
      SELECT b.*, c.name AS c_name, c.phone AS c_phone
      FROM bookings b JOIN customers c ON c.id = b.customer_id
      WHERE b.deleted = 0 AND (
        b.status IN ('booked', 'picked_up', 'dispatched')
        OR (b.status = 'returned' AND b.payable - COALESCE((
              SELECT SUM(p.amount) FROM payments p
              WHERE p.booking_id = b.id AND p.kind IN ('advance', 'balance')), 0) > 0.005)
      )
      ORDER BY b.pickup_date, b.id
    ''');
    return _hydrate(d, rows);
  }

  Future<Booking?> get(int id) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.rawQuery(
      '''
      SELECT b.*, c.name AS c_name, c.phone AS c_phone
      FROM bookings b JOIN customers c ON c.id = b.customer_id
      WHERE b.id = ? AND b.deleted = 0
    ''',
      [id],
    );
    if (rows.isEmpty) return null;
    return (await _hydrate(d, rows)).first;
  }

  Future<List<Booking>> _hydrate(
    DatabaseExecutor d,
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) return const [];
    final ids = [for (final r in rows) r['id'] as int];
    final marks = List.filled(ids.length, '?').join(',');
    final lineRows = await d.rawQuery(
      'SELECT * FROM booking_items WHERE booking_id IN ($marks) ORDER BY id',
      ids,
    );
    final payRows = await d.rawQuery(
      'SELECT * FROM payments WHERE booking_id IN ($marks) ORDER BY paid_at, id',
      ids,
    );
    final photoRows = await d.rawQuery(
      'SELECT * FROM booking_photos WHERE booking_id IN ($marks) ORDER BY id',
      ids,
    );
    final chargeRows = await d.rawQuery(
      'SELECT * FROM booking_charges WHERE booking_id IN ($marks) ORDER BY created_at, id',
      ids,
    );
    List<T> pick<T>(
      List<Map<String, Object?>> src,
      int id,
      T Function(Map<String, Object?>) make,
    ) => [
      for (final r in src)
        if (r['booking_id'] == id) make(r),
    ];

    return [
      for (final r in rows)
        Booking(
          id: r['id'] as int,
          uuid: r['uuid'] as String,
          number: r['number'] as int,
          customerId: r['customer_id'] as int,
          customerName: r['c_name'] as String,
          customerPhone: (r['c_phone'] as String?) ?? '',
          eventDate: _day(r['event_date']),
          pickupDate: _day(r['pickup_date']),
          returnDate: _day(r['return_date']),
          status: BookingStatus.fromDb(r['status'] as String?),
          rentTotal: (r['rent_total'] as num).toDouble(),
          depositTotal: (r['deposit_total'] as num).toDouble(),
          discount: (r['discount'] as num).toDouble(),
          taxTotal: (r['tax_total'] as num).toDouble(),
          payable: (r['payable'] as num).toDouble(),
          notes: (r['notes'] as String?) ?? '',
          remindDays: (r['remind_days'] as int?) ?? 2,
          eventTime: (r['event_time'] as String?) ?? '',
          createdBy: (r['created_by'] as String?) ?? '',
          courierName: (r['courier_name'] as String?) ?? '',
          courierNo: (r['courier_no'] as String?) ?? '',
          dispatchedAt: r['dispatched_at'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(r['dispatched_at'] as int),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            r['created_at'] as int,
          ),
          charges: pick(
            chargeRows,
            r['id'] as int,
            (c) => BookingCharge(
              id: c['id'] as int,
              bookingId: c['booking_id'] as int,
              kind: ChargeKind.fromName(c['kind'] as String?),
              amount: (c['amount'] as num).toDouble(),
              note: (c['note'] as String?) ?? '',
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                c['created_at'] as int,
              ),
            ),
          ),
          lines: pick(
            lineRows,
            r['id'] as int,
            (l) => BookingLine(
              itemId: l['item_id'] as int,
              name: l['name'] as String,
              rateType: RateType.fromName(l['rate_type'] as String?),
              qty: ((l['qty'] as num?)?.toInt() ?? 1).clamp(1, 1 << 30),
              rate: (l['rate'] as num).toDouble(),
              deposit: (l['deposit'] as num).toDouble(),
              amount: (l['amount'] as num).toDouble(),
              hsn: (l['hsn'] as String?) ?? '',
              gstRate: (l['gst_rate'] as num).toDouble(),
              taxable: (l['taxable'] as num).toDouble(),
              tax: (l['tax'] as num).toDouble(),
            ),
          ),
          payments: pick(
            payRows,
            r['id'] as int,
            (p) => Payment(
              id: p['id'] as int,
              bookingId: p['booking_id'] as int,
              kind: PaymentKind.fromName(p['kind'] as String?),
              amount: (p['amount'] as num).toDouble(),
              mode: PayMode.fromName(p['mode'] as String?),
              note: (p['note'] as String?) ?? '',
              paidAt: DateTime.fromMillisecondsSinceEpoch(p['paid_at'] as int),
            ),
          ),
          photos: pick(
            photoRows,
            r['id'] as int,
            (p) => BookingPhoto(
              id: p['id'] as int,
              bookingId: p['booking_id'] as int,
              stage: p['stage'] as String,
              path: p['path'] as String,
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                p['created_at'] as int,
              ),
            ),
          ),
        ),
    ];
  }

  static DateTime _day(Object? ms) =>
      dayOf(DateTime.fromMillisecondsSinceEpoch(ms as int));

  /// How many bookings were made in the calendar month of [now], cancelled
  /// ones included: they used up a place on the free plan.
  Future<int> createdInMonth([DateTime? now]) async {
    final d = await AppDatabase.instance.db;
    return _createdInMonth(d, now ?? DateTime.now());
  }

  Future<int> _createdInMonth(DatabaseExecutor d, DateTime now) async {
    final from = monthStart(now).millisecondsSinceEpoch;
    final to = DateTime(now.year, now.month + 1).millisecondsSinceEpoch;
    final r = await d.rawQuery(
      'SELECT COUNT(*) AS n FROM bookings WHERE deleted = 0 '
      'AND created_at >= ? AND created_at < ?',
      [from, to],
    );
    return (r.first['n'] as int?) ?? 0;
  }

  /// New bookings the free plan still allows this month.
  Future<int> freeLeft([DateTime? now]) async {
    final left = FreePlan.bookingsPerMonth - await createdInMonth(now);
    return left < 0 ? 0 : left;
  }

  /// The items among [itemIds] that do not have enough free pieces for any day
  /// from [pickup] to [ret]. [quantities] says how many of each are wanted
  /// (one when not listed). A booking that is out and late keeps its pieces
  /// until they are brought back. [exceptBookingId] leaves one booking out, for
  /// editing it.
  Future<Map<int, ItemConflict>> conflicts({
    required List<int> itemIds,
    required DateTime pickup,
    required DateTime ret,
    Map<int, int> quantities = const {},
    int? exceptBookingId,
    DateTime? now,
  }) async {
    final d = await AppDatabase.instance.db;
    return _conflicts(d, itemIds, quantities, pickup, ret, exceptBookingId, now);
  }

  /// For each of [itemIds]: how many pieces the shop has and how many are free
  /// on every day from [pickup] to [ret].
  Future<Map<int, ItemAvailability>> availability({
    required List<int> itemIds,
    required DateTime pickup,
    required DateTime ret,
    int? exceptBookingId,
    DateTime? now,
  }) async {
    final d = await AppDatabase.instance.db;
    return _availability(d, itemIds, pickup, ret, exceptBookingId, now);
  }

  Future<Map<int, ItemConflict>> _conflicts(
    DatabaseExecutor d,
    List<int> itemIds,
    Map<int, int> quantities,
    DateTime pickup,
    DateTime ret,
    int? exceptBookingId,
    DateTime? now,
  ) async {
    final avail = await _availability(
      d,
      itemIds,
      pickup,
      ret,
      exceptBookingId,
      now,
    );
    final out = <int, ItemConflict>{};
    for (final a in avail.values) {
      final wanted = (quantities[a.itemId] ?? 1).clamp(1, 1 << 30);
      if (wanted <= a.free) continue;
      final h = a.holder;
      out[a.itemId] = ItemConflict(
        itemId: a.itemId,
        bookingId: h?.bookingId ?? 0,
        bookingNumber: h?.bookingNumber ?? 0,
        customerName: h?.customerName ?? '',
        pickupDate: h?.pickupDate ?? pickup,
        returnDate: h?.returnDate ?? ret,
        stock: a.stock,
        free: a.free,
      );
    }
    return out;
  }

  Future<Map<int, ItemAvailability>> _availability(
    DatabaseExecutor d,
    List<int> itemIds,
    DateTime pickup,
    DateTime ret,
    int? exceptBookingId,
    DateTime? now,
  ) async {
    if (itemIds.isEmpty) return const {};
    final today = dayOf(now ?? DateTime.now());
    final marks = List.filled(itemIds.length, '?').join(',');
    final stockRows = await d.rawQuery(
      'SELECT id, quantity FROM items WHERE id IN ($marks)',
      itemIds,
    );
    final stock = {
      for (final r in stockRows)
        r['id'] as int: ((r['quantity'] as num?)?.toInt() ?? 1).clamp(1, 1 << 30),
    };
    final rows = await d.rawQuery('''
      SELECT bi.item_id, bi.qty, b.id AS booking_id, b.number, b.pickup_date,
             b.return_date, b.status, c.name AS c_name
      FROM booking_items bi
      JOIN bookings b ON b.id = bi.booking_id
      JOIN customers c ON c.id = b.customer_id
      WHERE b.deleted = 0 AND b.status IN ('booked', 'picked_up', 'dispatched')
        AND bi.item_id IN ($marks)
    ''', itemIds);
    // the bookings that share a day with the dates asked about, per item
    final overlaps = <int, List<({DateTime from, DateTime to, int qty, ItemConflict who})>>{};
    for (final r in rows) {
      final bookingId = r['booking_id'] as int;
      if (bookingId == exceptBookingId) continue;
      final from = _day(r['pickup_date']);
      var to = _day(r['return_date']);
      // still out and late: it is not back, so it is held until it is
      if (r['status'] != 'booked' && to.isBefore(today)) to = today;
      if (!rangesOverlap(pickup, ret, from, to)) continue;
      final id = r['item_id'] as int;
      overlaps.putIfAbsent(id, () => []).add((
        from: from,
        to: to,
        qty: ((r['qty'] as num?)?.toInt() ?? 1).clamp(1, 1 << 30),
        who: ItemConflict(
          itemId: id,
          bookingId: bookingId,
          bookingNumber: r['number'] as int,
          customerName: r['c_name'] as String,
          pickupDate: from,
          returnDate: to,
        ),
      ));
    }
    final p0 = dayOf(pickup), r0 = dayOf(ret);
    final out = <int, ItemAvailability>{};
    for (final id in itemIds) {
      final have = stock[id] ?? 1;
      final list = overlaps[id] ?? const [];
      // The most pieces held on any single day is found on the first day or
      // on a day some booking starts, so only those days need counting.
      final days = <DateTime>{
        p0,
        for (final o in list)
          if (!o.from.isBefore(p0) && !o.from.isAfter(r0)) o.from,
      };
      var peak = 0;
      for (final day in days) {
        var used = 0;
        for (final o in list) {
          if (!day.isBefore(o.from) && !day.isAfter(o.to)) used += o.qty;
        }
        if (used > peak) peak = used;
      }
      final free = have - peak < 0 ? 0 : have - peak;
      ItemConflict? holder;
      if (list.isNotEmpty) {
        final first = list.first.who;
        holder = ItemConflict(
          itemId: id,
          bookingId: first.bookingId,
          bookingNumber: first.bookingNumber,
          customerName: first.customerName,
          pickupDate: first.pickupDate,
          returnDate: first.returnDate,
          stock: have,
          free: free,
        );
      }
      out[id] = ItemAvailability(
        itemId: id,
        stock: have,
        free: free,
        holder: holder,
      );
    }
    return out;
  }

  /// Makes a booking. Throws [BookingException] when it cannot be made:
  /// the free month is used up (unless [isPro]), the dates are wrong, no item
  /// was chosen, an item cannot be booked or is already taken.
  /// [advance] is recorded as a payment at the same moment.
  Future<int> create(
    BookingDraft draft, {
    required bool isPro,
    double advance = 0,
    PayMode advanceMode = PayMode.cash,
    GstConfig gst = GstConfig.off,
    bool checkAvailability = true,
    DateTime? now,
  }) async {
    final d = await AppDatabase.instance.db;
    final at = now ?? DateTime.now();
    return d.transaction((txn) async {
      if (!isPro && await _createdInMonth(txn, at) >= FreePlan.bookingsPerMonth) {
        throw const BookingException(BookingError.limitReached);
      }
      final p = await _prepare(txn, draft, null, at, gst, checkAvailability);
      if (advance < 0 || advance > p.payable + 0.005) {
        throw const BookingException(BookingError.badAmount);
      }
      final number =
          ((await txn.rawQuery('SELECT MAX(number) AS n FROM bookings')).first['n']
                  as int? ??
              0) +
          1;
      final ms = at.millisecondsSinceEpoch;
      final id = await txn.insert('bookings', {
        'uuid': newUuid(),
        'updated_at': ms,
        'number': number,
        'customer_id': draft.customerId,
        'event_date': dayOf(draft.eventDate).millisecondsSinceEpoch,
        'pickup_date': dayOf(draft.pickupDate).millisecondsSinceEpoch,
        'return_date': dayOf(draft.returnDate).millisecondsSinceEpoch,
        'status': BookingStatus.booked.db,
        'rent_total': p.rent,
        'deposit_total': p.deposit,
        'discount': draft.discount,
        'tax_total': p.tax,
        'payable': p.payable,
        'notes': draft.notes.trim(),
        'remind_days': draft.remindDays,
        'event_time': draft.eventTime,
        'created_by': draft.createdBy.trim(),
        'created_at': ms,
      });
      await _insertLines(txn, id, p.lines);
      if (advance > 0.004) {
        await txn.insert('payments', {
          'booking_id': id,
          'kind': PaymentKind.advance.name,
          'amount': advance,
          'mode': advanceMode.name,
          'note': '',
          'paid_at': ms,
        });
      }
      return id;
    });
  }

  /// Changes a booking that has not been returned or cancelled. The items,
  /// dates and discount are checked again; payments are left as they are.
  Future<void> update(
    int id,
    BookingDraft draft, {
    GstConfig gst = GstConfig.off,
    bool checkAvailability = true,
    DateTime? now,
  }) async {
    final d = await AppDatabase.instance.db;
    final at = now ?? DateTime.now();
    await d.transaction((txn) async {
      final cur = await _status(txn, id);
      if (!cur.holdsItems) {
        throw const BookingException(BookingError.badState);
      }
      final p = await _prepare(txn, draft, id, at, gst, checkAvailability);
      // charges added at return stay part of what is owed
      final charged = ((await txn.query(
                'bookings',
                columns: ['extra_charges'],
                where: 'id = ?',
                whereArgs: [id],
              )).first['extra_charges'] as num?)
              ?.toDouble() ??
          0;
      await txn.update(
        'bookings',
        {
          'customer_id': draft.customerId,
          'event_date': dayOf(draft.eventDate).millisecondsSinceEpoch,
          'pickup_date': dayOf(draft.pickupDate).millisecondsSinceEpoch,
          'return_date': dayOf(draft.returnDate).millisecondsSinceEpoch,
          'rent_total': p.rent,
          'deposit_total': p.deposit,
          'discount': draft.discount,
          'tax_total': p.tax,
          'payable': r2(p.payable + charged),
          'notes': draft.notes.trim(),
          'remind_days': draft.remindDays,
          'event_time': draft.eventTime,
          'updated_at': at.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.delete('booking_items', where: 'booking_id = ?', whereArgs: [id]);
      await _insertLines(txn, id, p.lines);
    });
  }

  void _checkDiscount(double discount, double rent) {
    if (discount < 0 || discount > rent + 0.005) {
      throw const BookingException(BookingError.badDiscount);
    }
  }

  Future<BookingStatus> _status(DatabaseExecutor d, int id) async {
    final r = await d.query(
      'bookings',
      columns: ['status'],
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
    if (r.isEmpty) throw const BookingException(BookingError.badState);
    return BookingStatus.fromDb(r.first['status'] as String?);
  }

  /// Checks the dates, items and discount of [draft] and works out each line
  /// and the totals.
  Future<_Prepared> _prepare(
    DatabaseExecutor d,
    BookingDraft draft,
    int? exceptBookingId,
    DateTime now,
    GstConfig gst,
    bool checkAvailability,
  ) async {
    final pickup = dayOf(draft.pickupDate);
    final event = dayOf(draft.eventDate);
    final ret = dayOf(draft.returnDate);
    if (event.isBefore(pickup) || ret.isBefore(event)) {
      throw const BookingException(BookingError.badDates);
    }
    final ids = draft.itemIds.toSet().toList();
    if (ids.isEmpty) throw const BookingException(BookingError.noItems);

    final marks = List.filled(ids.length, '?').join(',');
    final rows = await d.rawQuery(
      'SELECT * FROM items WHERE id IN ($marks)',
      ids,
    );
    final byId = {for (final r in rows) r['id'] as int: r};
    final amounts = <double>[];
    final rates = <double>[];
    final base = <Map<String, Object?>>[];
    for (final id in ids) {
      final r = byId[id];
      if (r == null ||
          r['deleted'] == 1 ||
          ItemStatus.fromName(r['status'] as String?) != ItemStatus.active) {
        throw BookingException(
          BookingError.itemUnavailable,
          (r?['name'] as String?) ?? '',
        );
      }
      final type = RateType.fromName(r['rate_type'] as String?);
      final rate = (r['rate'] as num).toDouble();
      final qty = draft.qtyOf(id);
      amounts.add(r2(lineAmount(type, rate, pickup, ret) * qty));
      rates.add((r['gst_rate'] as num?)?.toDouble() ?? 0);
      base.add({
        'item_id': id,
        'name': r['name'],
        'rate_type': type.name,
        'qty': qty,
        'rate': rate,
        'deposit': (r['deposit'] as num).toDouble(),
        'hsn': (r['hsn'] as String?) ?? '',
      });
    }
    final rent = r2(amounts.fold(0.0, (a, b) => a + b));
    _checkDiscount(draft.discount, rent);
    final money = splitMoney(
      amounts: amounts,
      gstRates: rates,
      discount: draft.discount,
      gst: gst,
    );
    final lines = <Map<String, Object?>>[
      for (var i = 0; i < base.length; i++)
        {
          ...base[i],
          'amount': amounts[i],
          'gst_rate': gst.enabled ? rates[i] : 0.0,
          'taxable': money[i].taxable,
          'tax': money[i].tax,
        },
    ];
    final clash = checkAvailability
        ? await _conflicts(
            d,
            ids,
            draft.quantities,
            pickup,
            ret,
            exceptBookingId,
            now,
          )
        : const <int, ItemConflict>{};
    if (clash.isNotEmpty) {
      final first = clash.values.first;
      final name = byId[first.itemId]!['name'] as String;
      final pieces = first.stock > 1 || draft.qtyOf(first.itemId) > 1;
      throw BookingException(
        pieces ? BookingError.notEnough : BookingError.itemBusy,
        name,
      );
    }
    return _Prepared(
      lines: lines,
      rent: rent,
      deposit: r2(
        base.fold(
          0.0,
          (a, l) => a + (l['deposit']! as double) * (l['qty']! as int),
        ),
      ),
      tax: r2(money.fold(0.0, (a, m) => a + m.tax)),
      payable: r2(money.fold(0.0, (a, m) => a + m.total)),
    );
  }

  Future<void> _insertLines(
    DatabaseExecutor d,
    int bookingId,
    List<Map<String, Object?>> lines,
  ) async {
    for (final l in lines) {
      await d.insert('booking_items', {'booking_id': bookingId, ...l});
    }
  }

  /// The items go out. Only a booked booking can be picked up.
  Future<void> markPickedUp(int id, {DateTime? now}) =>
      _move(id, BookingStatus.booked, BookingStatus.pickedUp, now);

  /// The items are sent by courier. Only a booked booking can be dispatched.
  /// The courier's name and the tracking number are optional.
  Future<void> markDispatched(
    int id, {
    String courierName = '',
    String courierNo = '',
    DateTime? now,
  }) async {
    final d = await AppDatabase.instance.db;
    final at = now ?? DateTime.now();
    await d.transaction((txn) async {
      if (await _status(txn, id) != BookingStatus.booked) {
        throw const BookingException(BookingError.badState);
      }
      await txn.update(
        'bookings',
        {
          'status': BookingStatus.dispatched.db,
          'courier_name': courierName.trim(),
          'courier_no': courierNo.trim(),
          'dispatched_at': at.millisecondsSinceEpoch,
          'updated_at': at.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Corrects the courier's name or the tracking number of a dispatched
  /// booking.
  Future<void> updateCourier(
    int id, {
    required String courierName,
    required String courierNo,
    DateTime? now,
  }) async {
    final d = await AppDatabase.instance.db;
    await d.transaction((txn) async {
      final s = await _status(txn, id);
      if (s != BookingStatus.dispatched && s != BookingStatus.returned) {
        throw const BookingException(BookingError.badState);
      }
      await txn.update(
        'bookings',
        {
          'courier_name': courierName.trim(),
          'courier_no': courierNo.trim(),
          'updated_at': (now ?? DateTime.now()).millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// The items come back. Only a booking whose items are out (collected or
  /// dispatched) can be returned.
  Future<void> markReturned(int id, {DateTime? now}) async {
    final d = await AppDatabase.instance.db;
    await d.transaction((txn) async {
      if (!(await _status(txn, id)).isOut) {
        throw const BookingException(BookingError.badState);
      }
      await txn.update(
        'bookings',
        {
          'status': BookingStatus.returned.db,
          'updated_at': (now ?? DateTime.now()).millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Adds a late-return or damage charge. It is added to what the customer
  /// owes. Only a booking whose items have gone out, or are back, can be
  /// charged.
  Future<int> addCharge(
    int bookingId, {
    required ChargeKind kind,
    required double amount,
    String note = '',
    DateTime? now,
  }) async {
    final amt = r2(amount);
    if (amt <= 0.004) throw const BookingException(BookingError.badAmount);
    final d = await AppDatabase.instance.db;
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return d.transaction((txn) async {
      final s = await _status(txn, bookingId);
      if (!s.isOut && s != BookingStatus.returned) {
        throw const BookingException(BookingError.badState);
      }
      final id = await txn.insert('booking_charges', {
        'booking_id': bookingId,
        'kind': kind.name,
        'amount': amt,
        'note': note.trim(),
        'created_at': at,
      });
      await txn.rawUpdate(
        'UPDATE bookings SET payable = payable + ?, extra_charges = extra_charges + ?, updated_at = ? WHERE id = ?',
        [amt, amt, at, bookingId],
      );
      // the invoice already made for this booking gets the charge as a line
      final inv = await _activeInvoiceId(txn, bookingId);
      if (inv != null) {
        await txn.insert('invoice_items', {
          'invoice_id': inv,
          'name': chargeLineName(kind, note),
          'charge_id': id,
          'hsn': '',
          'rate_type': RateType.event.name,
          'rate': amt,
          'days': 1,
          'qty': 1,
          'gst_rate': 0.0,
          'taxable': amt,
          'cgst': 0.0,
          'sgst': 0.0,
          'igst': 0.0,
          'total': amt,
        });
        await _shiftInvoice(txn, inv, amt, at);
      }
      return id;
    });
  }

  Future<int?> _activeInvoiceId(DatabaseExecutor d, int bookingId) async {
    final rows = await d.query(
      'invoices',
      columns: ['id'],
      where: "booking_id = ? AND status = 'active' AND deleted = 0",
      whereArgs: [bookingId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  /// Moves an invoice's taxable value and total by [delta] (a charge is not
  /// taxed, so both change by the same amount).
  Future<void> _shiftInvoice(
    DatabaseExecutor d,
    int invoiceId,
    double delta,
    int at,
  ) => d.rawUpdate(
    'UPDATE invoices SET taxable = taxable + ?, total = total + ?, updated_at = ? WHERE id = ?',
    [delta, delta, at, invoiceId],
  );

  /// Takes a charge off again (it was added by mistake or waived). When the
  /// customer had already paid it, what they paid beyond the new total is
  /// recorded as a negative balance payment ("refund of a removed charge"),
  /// so the books show the money going back and the booking is not overpaid.
  Future<void> removeCharge(int chargeId, {DateTime? now}) async {
    final d = await AppDatabase.instance.db;
    await d.transaction((txn) async {
      final rows = await txn.query(
        'booking_charges',
        where: 'id = ?',
        whereArgs: [chargeId],
      );
      if (rows.isEmpty) return;
      final bookingId = rows.first['booking_id'] as int;
      final amt = (rows.first['amount'] as num).toDouble();
      final b = await _load(txn, bookingId);
      final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
      final excess = r2(b.rentPaid - (b.payable - amt));
      await txn.delete('booking_charges', where: 'id = ?', whereArgs: [chargeId]);
      await txn.rawUpdate(
        'UPDATE bookings SET payable = payable - ?, extra_charges = extra_charges - ?, updated_at = ? WHERE id = ?',
        [amt, amt, at, bookingId],
      );
      // and comes off the invoice again (found by the charge's id; an
      // invoice made before that has no such line and is left as it is)
      final inv = await _activeInvoiceId(txn, bookingId);
      if (inv != null) {
        final gone = await txn.delete(
          'invoice_items',
          where: 'invoice_id = ? AND charge_id = ?',
          whereArgs: [inv, chargeId],
        );
        if (gone > 0) await _shiftInvoice(txn, inv, -amt, at);
      }
      if (excess > 0.005) {
        await txn.insert('payments', {
          'booking_id': bookingId,
          'kind': PaymentKind.balance.name,
          'amount': -excess,
          'mode': PayMode.cash.name,
          'note': 'Refund of a removed charge',
          'paid_at': at,
        });
      }
    });
  }

  /// Every booking of one customer, newest first (cancelled ones included, so
  /// the history is complete).
  Future<List<Booking>> forCustomer(int customerId) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.rawQuery(
      '''
      SELECT b.*, c.name AS c_name, c.phone AS c_phone
      FROM bookings b JOIN customers c ON c.id = b.customer_id
      WHERE b.deleted = 0 AND b.customer_id = ?
      ORDER BY b.event_date DESC, b.id DESC
    ''',
      [customerId],
    );
    return _hydrate(d, rows);
  }

  /// Bookings whose items are held on some day from [from] to [to] (both
  /// included): booked, collected or dispatched. A booking that is out and
  /// late is held up to today. For the availability calendar.
  Future<List<Booking>> heldBetween(
    DateTime from,
    DateTime to, {
    DateTime? now,
  }) async {
    final d = await AppDatabase.instance.db;
    final today = dayOf(now ?? DateTime.now());
    final rows = await d.rawQuery(
      '''
      SELECT b.*, c.name AS c_name, c.phone AS c_phone
      FROM bookings b JOIN customers c ON c.id = b.customer_id
      WHERE b.deleted = 0 AND b.status IN ('booked', 'picked_up', 'dispatched')
        AND b.pickup_date <= ?
        AND (b.return_date >= ? OR (b.status != 'booked' AND ? >= ?))
      ORDER BY b.pickup_date, b.id
    ''',
      [
        dayOf(to).millisecondsSinceEpoch,
        dayOf(from).millisecondsSinceEpoch,
        today.millisecondsSinceEpoch,
        dayOf(from).millisecondsSinceEpoch,
      ],
    );
    return _hydrate(d, rows);
  }

  /// A service booking (makeup) is finished: it goes straight from booked to
  /// done, because nothing was picked up or brought back.
  Future<void> markDone(int id, {DateTime? now}) =>
      _move(id, BookingStatus.booked, BookingStatus.returned, now);

  /// Calls the booking off. Only a booking whose items have not gone out can
  /// be cancelled.
  Future<void> cancel(int id, {DateTime? now}) =>
      _move(id, BookingStatus.booked, BookingStatus.cancelled, now);

  Future<void> _move(
    int id,
    BookingStatus from,
    BookingStatus to,
    DateTime? now,
  ) async {
    final d = await AppDatabase.instance.db;
    await d.transaction((txn) async {
      if (await _status(txn, id) != from) {
        throw const BookingException(BookingError.badState);
      }
      await txn.update(
        'bookings',
        {
          'status': to.db,
          'updated_at': (now ?? DateTime.now()).millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Records money taken or given back. Rent payments cannot be more than the
  /// rent still due, and a refund cannot be more than the deposit held.
  Future<void> addPayment(
    int bookingId, {
    required PaymentKind kind,
    required double amount,
    PayMode mode = PayMode.cash,
    String note = '',
    DateTime? at,
  }) async {
    if (amount <= 0.004) throw const BookingException(BookingError.badAmount);
    final d = await AppDatabase.instance.db;
    await d.transaction((txn) async {
      final status = await _status(txn, bookingId);
      if (status == BookingStatus.cancelled && kind != PaymentKind.refund) {
        throw const BookingException(BookingError.badState);
      }
      final b = await _load(txn, bookingId);
      final limit = switch (kind) {
        PaymentKind.advance || PaymentKind.balance => b.balanceDue,
        PaymentKind.deposit => b.depositDue,
        PaymentKind.refund => b.depositHeld,
      };
      if (amount > limit + 0.005) {
        throw const BookingException(BookingError.badAmount);
      }
      await txn.insert('payments', {
        'booking_id': bookingId,
        'kind': kind.name,
        'amount': amount,
        'mode': mode.name,
        'note': note.trim(),
        'paid_at': (at ?? DateTime.now()).millisecondsSinceEpoch,
      });
    });
  }

  Future<Booking> _load(DatabaseExecutor d, int id) async {
    final rows = await d.rawQuery(
      '''
      SELECT b.*, c.name AS c_name, c.phone AS c_phone
      FROM bookings b JOIN customers c ON c.id = b.customer_id
      WHERE b.id = ?
    ''',
      [id],
    );
    return (await _hydrate(d, rows)).first;
  }

  /// Adds a photo (a file already saved in the app's folder). The free plan
  /// keeps [FreePlan.photosPerBooking] photos on a booking; [isPro] lifts it.
  Future<int> addPhoto(
    int bookingId, {
    required String path,
    required String stage,
    required bool isPro,
    DateTime? now,
  }) async {
    final d = await AppDatabase.instance.db;
    final n = Sqflite.firstIntValue(
      await d.rawQuery(
        'SELECT COUNT(*) FROM booking_photos WHERE booking_id = ?',
        [bookingId],
      ),
    )!;
    if (!isPro && n >= FreePlan.photosPerBooking) {
      throw const BookingException(BookingError.limitReached);
    }
    return d.insert('booking_photos', {
      'booking_id': bookingId,
      'stage': stage,
      'path': path,
      'created_at': (now ?? DateTime.now()).millisecondsSinceEpoch,
    });
  }

  Future<void> removePhoto(int photoId) async {
    final d = await AppDatabase.instance.db;
    await d.delete('booking_photos', where: 'id = ?', whereArgs: [photoId]);
  }
}

final bookingRepoProvider = Provider<BookingRepo>((_) => BookingRepo());

/// What the Bookings list is showing.
final bookingFilterProvider = StateProvider.autoDispose<BookingFilter>(
  (_) => BookingFilter.upcoming,
);
final bookingSearchProvider = StateProvider.autoDispose<String>((_) => '');

final bookingsProvider = FutureProvider.autoDispose<List<Booking>>((ref) {
  final filter = ref.watch(bookingFilterProvider);
  final q = ref.watch(bookingSearchProvider);
  return ref.watch(bookingRepoProvider).list(filter: filter, query: q);
});

/// Every booking of one customer, newest first.
final customerBookingsProvider = FutureProvider.autoDispose
    .family<List<Booking>, int>(
      (ref, customerId) => ref.watch(bookingRepoProvider).forCustomer(customerId),
    );

/// One booking with its lines, payments and photos.
/// What needs doing today (see [buildReminders]).
final remindersProvider = FutureProvider.autoDispose<List<ReminderItem>>((
  ref,
) async {
  final all = await ref.watch(bookingRepoProvider).forReminders();
  return buildReminders(all, DateTime.now());
});

final bookingProvider = FutureProvider.autoDispose.family<Booking?, int>(
  (ref, id) => ref.watch(bookingRepoProvider).get(id),
);
