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

/// Why a booking could not be saved or changed.
enum BookingError {
  /// The free plan's bookings for this month are used up.
  limitReached,

  /// An item is already booked for some of these days.
  itemBusy,

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
  final double discount;
  final String notes;
  final int remindDays;

  const BookingDraft({
    required this.customerId,
    required this.eventDate,
    required this.pickupDate,
    required this.returnDate,
    required this.itemIds,
    this.discount = 0,
    this.notes = '',
    this.remindDays = 2,
  });
}

/// An item that is already taken for the days asked about.
class ItemConflict {
  final int itemId;
  final int bookingId;
  final int bookingNumber;
  final String customerName;
  final DateTime pickupDate;
  final DateTime returnDate;

  const ItemConflict({
    required this.itemId,
    required this.bookingId,
    required this.bookingNumber,
    required this.customerName,
    required this.pickupDate,
    required this.returnDate,
  });
}

/// Which bookings the list shows.
enum BookingFilter {
  upcoming('Upcoming'),
  out('Out'),
  returned('Returned'),
  cancelled('Cancelled');

  final String en;
  const BookingFilter(this.en);

  BookingStatus get status => switch (this) {
    upcoming => BookingStatus.booked,
    out => BookingStatus.pickedUp,
    returned => BookingStatus.returned,
    cancelled => BookingStatus.cancelled,
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
    final where = StringBuffer('b.deleted = 0 AND b.status = ?');
    final args = <Object?>[filter.status.db];
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
        filter == BookingFilter.upcoming || filter == BookingFilter.out;
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
    final rows = await d.rawQuery('''
      SELECT b.*, c.name AS c_name, c.phone AS c_phone
      FROM bookings b JOIN customers c ON c.id = b.customer_id
      WHERE b.deleted = 0 AND (
        b.status IN ('booked', 'picked_up')
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
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            r['created_at'] as int,
          ),
          lines: pick(
            lineRows,
            r['id'] as int,
            (l) => BookingLine(
              itemId: l['item_id'] as int,
              name: l['name'] as String,
              rateType: RateType.fromName(l['rate_type'] as String?),
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

  /// The items among [itemIds] that are taken for any day from [pickup] to
  /// [ret]. An item whose booking is out and late stays taken until it is
  /// brought back. [exceptBookingId] leaves one booking out, for editing it.
  Future<Map<int, ItemConflict>> conflicts({
    required List<int> itemIds,
    required DateTime pickup,
    required DateTime ret,
    int? exceptBookingId,
    DateTime? now,
  }) async {
    final d = await AppDatabase.instance.db;
    return _conflicts(d, itemIds, pickup, ret, exceptBookingId, now);
  }

  Future<Map<int, ItemConflict>> _conflicts(
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
    final rows = await d.rawQuery('''
      SELECT bi.item_id, b.id AS booking_id, b.number, b.pickup_date,
             b.return_date, b.status, c.name AS c_name
      FROM booking_items bi
      JOIN bookings b ON b.id = bi.booking_id
      JOIN customers c ON c.id = b.customer_id
      WHERE b.deleted = 0 AND b.status IN ('booked', 'picked_up')
        AND bi.item_id IN ($marks)
    ''', itemIds);
    final out = <int, ItemConflict>{};
    for (final r in rows) {
      final bookingId = r['booking_id'] as int;
      if (bookingId == exceptBookingId) continue;
      final from = _day(r['pickup_date']);
      var to = _day(r['return_date']);
      // still out and late: it is not back, so it is taken until it is
      if (r['status'] == 'picked_up' && to.isBefore(today)) to = today;
      if (!rangesOverlap(pickup, ret, from, to)) continue;
      out.putIfAbsent(
        r['item_id'] as int,
        () => ItemConflict(
          itemId: r['item_id'] as int,
          bookingId: bookingId,
          bookingNumber: r['number'] as int,
          customerName: r['c_name'] as String,
          pickupDate: from,
          returnDate: to,
        ),
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
    DateTime? now,
  }) async {
    final d = await AppDatabase.instance.db;
    final at = now ?? DateTime.now();
    return d.transaction((txn) async {
      if (!isPro && await _createdInMonth(txn, at) >= FreePlan.bookingsPerMonth) {
        throw const BookingException(BookingError.limitReached);
      }
      final p = await _prepare(txn, draft, null, at, gst);
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
    DateTime? now,
  }) async {
    final d = await AppDatabase.instance.db;
    final at = now ?? DateTime.now();
    await d.transaction((txn) async {
      final cur = await _status(txn, id);
      if (!cur.holdsItems) {
        throw const BookingException(BookingError.badState);
      }
      final p = await _prepare(txn, draft, id, at, gst);
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
          'payable': p.payable,
          'notes': draft.notes.trim(),
          'remind_days': draft.remindDays,
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
      amounts.add(lineAmount(type, rate, pickup, ret));
      rates.add((r['gst_rate'] as num?)?.toDouble() ?? 0);
      base.add({
        'item_id': id,
        'name': r['name'],
        'rate_type': type.name,
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
    final clash = await _conflicts(d, ids, pickup, ret, exceptBookingId, now);
    if (clash.isNotEmpty) {
      final first = clash.values.first;
      throw BookingException(
        BookingError.itemBusy,
        byId[first.itemId]!['name'] as String,
      );
    }
    return _Prepared(
      lines: lines,
      rent: rent,
      deposit: r2(base.fold(0.0, (a, l) => a + (l['deposit']! as double))),
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

  /// The items come back. Only a picked-up booking can be returned.
  Future<void> markReturned(int id, {DateTime? now}) =>
      _move(id, BookingStatus.pickedUp, BookingStatus.returned, now);

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
