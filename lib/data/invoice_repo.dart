import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/booking_math.dart';
import '../core/format.dart';
import '../core/gst.dart';
import '../core/ids.dart';
import 'booking_models.dart';
import 'booking_repo.dart';
import 'database.dart';
import 'invoice_models.dart';
import 'models.dart';

class InvoiceRepo {
  /// Makes the invoice for a booking from the booking as it stands now.
  ///
  /// The customer's state decides CGST+SGST (same state as [shopStateCode], or
  /// no state given) or IGST. Throws [BookingException] with
  /// [BookingError.badState] when the booking is cancelled or already has an
  /// invoice (cancel that one first).
  Future<int> createForBooking(
    int bookingId, {
    required String shopStateCode,
    required String prefix,
    required bool gstEnabled,
    required bool taxInclusive,
    DateTime? now,
  }) async {
    final booking = await BookingRepo().get(bookingId);
    if (booking == null || booking.status == BookingStatus.cancelled) {
      throw const BookingException(BookingError.badState);
    }
    final d = await AppDatabase.instance.db;
    final at = now ?? DateTime.now();
    return d.transaction((txn) async {
      final existing = await txn.query(
        'invoices',
        columns: ['id'],
        where: "booking_id = ? AND status = 'active' AND deleted = 0",
        whereArgs: [bookingId],
      );
      if (existing.isNotEmpty) {
        throw const BookingException(BookingError.badState, 'invoice exists');
      }
      // read the customer even if they were removed from the list since
      final cust = await txn.query(
        'customers',
        where: 'id = ?',
        whereArgs: [booking.customerId],
      );
      final c = cust.isEmpty ? null : Customer.fromRow(cust.first);
      final gstin = (c?.gstin ?? '').trim().toUpperCase();
      var supply = (c?.stateCode ?? '').trim();
      if (supply.isEmpty && gstin.length >= 2) {
        final code = gstin.substring(0, 2);
        if (RegExp(r'^\d{2}$').hasMatch(code)) supply = code;
      }
      final inter = gstEnabled && isInterState(shopStateCode, supply);

      final number =
          ((await txn.rawQuery('SELECT MAX(number) AS n FROM invoices')).first['n']
                  as int? ??
              0) +
          1;
      final ms = at.millisecondsSinceEpoch;
      final days = rentalDays(booking.pickupDate, booking.returnDate);

      var cg = 0.0, sg = 0.0, ig = 0.0, taxable = 0.0, total = 0.0;
      final lines = <Map<String, Object?>>[];
      for (final l in booking.lines) {
        final tax = gstEnabled ? l.tax : 0.0;
        double lc = 0, ls = 0, li = 0;
        if (inter) {
          li = tax;
        } else {
          lc = r2(tax / 2);
          ls = r2(tax - lc);
        }
        cg += lc;
        sg += ls;
        ig += li;
        taxable += l.taxable;
        total += l.total;
        lines.add({
          'name': l.name,
          'hsn': l.hsn,
          'rate_type': l.rateType.name,
          'rate': l.rate,
          'days': l.rateType == RateType.day ? days : 1,
          'qty': l.qty,
          'gst_rate': gstEnabled ? l.gstRate : 0.0,
          'taxable': l.taxable,
          'cgst': lc,
          'sgst': ls,
          'igst': li,
          'total': l.total,
        });
      }
      final id = await txn.insert('invoices', {
        'uuid': newUuid(),
        'updated_at': ms,
        'booking_id': bookingId,
        'prefix': prefix.trim(),
        'number': number,
        'invoice_date': dayOf(at).millisecondsSinceEpoch,
        'status': 'active',
        'cust_name': booking.customerName,
        'cust_phone': booking.customerPhone,
        'cust_address': c?.address ?? '',
        'cust_gstin': gstin,
        'supply_state': supply,
        'inter_state': inter ? 1 : 0,
        'gst_enabled': gstEnabled ? 1 : 0,
        'tax_inclusive': taxInclusive ? 1 : 0,
        'discount': booking.discount,
        'taxable': r2(taxable),
        'cgst': r2(cg),
        'sgst': r2(sg),
        'igst': r2(ig),
        'total': r2(total),
        'event_date': dayOf(booking.eventDate).millisecondsSinceEpoch,
        'pickup_date': dayOf(booking.pickupDate).millisecondsSinceEpoch,
        'return_date': dayOf(booking.returnDate).millisecondsSinceEpoch,
        'created_at': ms,
      });
      for (final l in lines) {
        await txn.insert('invoice_items', {'invoice_id': id, ...l});
      }
      return id;
    });
  }

  static const _select = '''
    SELECT i.*, b.number AS b_number,
      COALESCE((SELECT SUM(p.amount) FROM payments p
        WHERE p.booking_id = i.booking_id
          AND p.kind IN ('advance', 'balance')), 0) AS paid
    FROM invoices i JOIN bookings b ON b.id = i.booking_id
  ''';

  /// Invoices, newest first. [from] up to (not including) [to] filters by
  /// invoice date; [query] matches the customer name, phone or the number.
  Future<List<Invoice>> list({
    DateTime? from,
    DateTime? to,
    String query = '',
    bool includeCancelled = true,
  }) async {
    final d = await AppDatabase.instance.db;
    final where = StringBuffer('i.deleted = 0');
    final args = <Object?>[];
    if (!includeCancelled) where.write(" AND i.status = 'active'");
    if (from != null) {
      where.write(' AND i.invoice_date >= ?');
      args.add(dayOf(from).millisecondsSinceEpoch);
    }
    if (to != null) {
      where.write(' AND i.invoice_date < ?');
      args.add(dayOf(to).millisecondsSinceEpoch);
    }
    final q = query.trim();
    if (q.isNotEmpty) {
      final like =
          '%${q.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      where.write(
        " AND (i.cust_name LIKE ? ESCAPE '\\' OR i.cust_phone LIKE ? ESCAPE '\\'"
        " OR i.prefix || '-' || printf('%04d', i.number) LIKE ? ESCAPE '\\')",
      );
      args.addAll([like, like, like]);
    }
    final rows = await d.rawQuery(
      '$_select WHERE $where ORDER BY i.invoice_date DESC, i.id DESC',
      args,
    );
    return _hydrate(rows, withLines: false);
  }

  Future<Invoice?> get(int id) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.rawQuery(
      '$_select WHERE i.id = ? AND i.deleted = 0',
      [id],
    );
    if (rows.isEmpty) return null;
    return (await _hydrate(rows, withLines: true)).first;
  }

  /// The booking's current (not cancelled) invoice, if it has one.
  Future<Invoice?> forBooking(int bookingId) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.rawQuery(
      "$_select WHERE i.booking_id = ? AND i.status = 'active' AND i.deleted = 0",
      [bookingId],
    );
    if (rows.isEmpty) return null;
    return (await _hydrate(rows, withLines: true)).first;
  }

  /// Cancels an invoice. Its number is not used again.
  Future<void> cancel(int id) async {
    final d = await AppDatabase.instance.db;
    await d.update(
      'invoices',
      {'status': 'cancelled', 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Invoice>> _hydrate(
    List<Map<String, Object?>> rows, {
    required bool withLines,
  }) async {
    final d = await AppDatabase.instance.db;
    final lineRows = <int, List<InvoiceLine>>{};
    if (withLines && rows.isNotEmpty) {
      final ids = [for (final r in rows) r['id'] as int];
      final marks = List.filled(ids.length, '?').join(',');
      for (final l in await d.rawQuery(
        'SELECT * FROM invoice_items WHERE invoice_id IN ($marks) ORDER BY id',
        ids,
      )) {
        lineRows.putIfAbsent(l['invoice_id'] as int, () => []).add(
          InvoiceLine(
            name: l['name'] as String,
            hsn: (l['hsn'] as String?) ?? '',
            rateType: RateType.fromName(l['rate_type'] as String?),
            rate: (l['rate'] as num).toDouble(),
            days: l['days'] as int,
            qty: ((l['qty'] as num?)?.toInt() ?? 1).clamp(1, 1 << 30),
            gstRate: (l['gst_rate'] as num).toDouble(),
            taxable: (l['taxable'] as num).toDouble(),
            cgst: (l['cgst'] as num).toDouble(),
            sgst: (l['sgst'] as num).toDouble(),
            igst: (l['igst'] as num).toDouble(),
            total: (l['total'] as num).toDouble(),
          ),
        );
      }
    }
    DateTime day(Object? ms) =>
        dayOf(DateTime.fromMillisecondsSinceEpoch(ms as int));
    double num0(Object? v) => (v as num?)?.toDouble() ?? 0;
    return [
      for (final r in rows)
        Invoice(
          id: r['id'] as int,
          uuid: r['uuid'] as String,
          bookingId: r['booking_id'] as int,
          prefix: (r['prefix'] as String?) ?? '',
          number: r['number'] as int,
          date: day(r['invoice_date']),
          cancelled: r['status'] == 'cancelled',
          customerName: (r['cust_name'] as String?) ?? '',
          customerPhone: (r['cust_phone'] as String?) ?? '',
          customerAddress: (r['cust_address'] as String?) ?? '',
          customerGstin: (r['cust_gstin'] as String?) ?? '',
          supplyState: (r['supply_state'] as String?) ?? '',
          interState: r['inter_state'] == 1,
          gstEnabled: r['gst_enabled'] == 1,
          taxInclusive: r['tax_inclusive'] == 1,
          discount: num0(r['discount']),
          taxable: num0(r['taxable']),
          cgst: num0(r['cgst']),
          sgst: num0(r['sgst']),
          igst: num0(r['igst']),
          total: num0(r['total']),
          eventDate: day(r['event_date']),
          pickupDate: day(r['pickup_date']),
          returnDate: day(r['return_date']),
          paid: num0(r['paid']),
          bookingNumber: (r['b_number'] as int?) ?? 0,
          lines: lineRows[r['id'] as int] ?? const [],
        ),
    ];
  }
}

final invoiceRepoProvider = Provider<InvoiceRepo>((_) => InvoiceRepo());

final invoiceSearchProvider = StateProvider.autoDispose<String>((_) => '');

final invoicesProvider = FutureProvider.autoDispose<List<Invoice>>((ref) {
  final q = ref.watch(invoiceSearchProvider);
  return ref.watch(invoiceRepoProvider).list(query: q);
});

final invoiceProvider = FutureProvider.autoDispose.family<Invoice?, int>(
  (ref, id) => ref.watch(invoiceRepoProvider).get(id),
);

/// The invoice of a booking, if it has one.
final bookingInvoiceProvider = FutureProvider.autoDispose.family<Invoice?, int>(
  (ref, bookingId) => ref.watch(invoiceRepoProvider).forBooking(bookingId),
);
