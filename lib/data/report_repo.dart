import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import 'database.dart';

/// A span of days: [from] up to, not including, [to].
typedef DateRange = ({DateTime from, DateTime to});

DateRange todayRange([DateTime? now]) {
  final d = dayOf(now ?? DateTime.now());
  return (from: d, to: DateTime(d.year, d.month, d.day + 1));
}

DateRange thisMonthRange([DateTime? now]) {
  final d = now ?? DateTime.now();
  return (from: DateTime(d.year, d.month), to: DateTime(d.year, d.month + 1));
}

DateRange lastMonthRange([DateTime? now]) {
  final d = now ?? DateTime.now();
  return (from: DateTime(d.year, d.month - 1), to: DateTime(d.year, d.month));
}

/// The Indian financial year (1 April to 31 March) that holds [now].
DateRange thisFinancialYearRange([DateTime? now]) {
  final d = now ?? DateTime.now();
  final start = d.month >= 4 ? d.year : d.year - 1;
  return (from: DateTime(start, 4), to: DateTime(start + 1, 4));
}

DateRange lastFinancialYearRange([DateTime? now]) {
  final cur = thisFinancialYearRange(now);
  return (from: DateTime(cur.from.year - 1, 4), to: cur.from);
}

class ItemSales {
  const ItemSales(this.name, this.count, this.amount);
  final String name;
  final int count;
  final double amount;
}

class CustomerSales {
  const CustomerSales(this.name, this.count, this.amount);
  final String name;
  final int count;
  final double amount;
}

/// The figures on the Reports page for a span of days. Bookings are placed in
/// the span by their event date; cancelled bookings are left out of money.
class ReportSummary {
  const ReportSummary({
    this.bookings = 0,
    this.cancelled = 0,
    this.billed = 0,
    this.tax = 0,
    this.collected = 0,
    this.outstanding = 0,
    this.depositsHeld = 0,
    this.topItems = const [],
    this.topCustomers = const [],
  });

  /// Bookings with an event in the span (not cancelled).
  final int bookings;
  final int cancelled;

  /// What those bookings come to, with GST (deposits are not included).
  final double billed;

  /// The GST inside [billed].
  final double tax;

  /// Rent payments taken in the span (whichever booking they are for).
  final double collected;

  /// Rent still to collect on those bookings.
  final double outstanding;

  /// Deposits the shop holds right now, on all bookings.
  final double depositsHeld;
  final List<ItemSales> topItems;
  final List<CustomerSales> topCustomers;
}

class ReportRepo {
  Future<ReportSummary> summary(DateRange r) async {
    final d = await AppDatabase.instance.db;
    final args = [r.from.millisecondsSinceEpoch, r.to.millisecondsSinceEpoch];
    double n(Object? v) => (v as num?)?.toDouble() ?? 0;

    final totals = (await d.rawQuery('''
      SELECT COUNT(*) AS c, COALESCE(SUM(payable), 0) AS billed,
             COALESCE(SUM(tax_total), 0) AS tax,
             COALESCE(SUM(payable - COALESCE((
               SELECT SUM(p.amount) FROM payments p
               WHERE p.booking_id = b.id AND p.kind IN ('advance','balance')), 0)), 0) AS due
      FROM bookings b
      WHERE b.deleted = 0 AND b.status != 'cancelled'
        AND b.event_date >= ? AND b.event_date < ?
    ''', args)).first;

    final cancelled = (await d.rawQuery(
      "SELECT COUNT(*) AS c FROM bookings WHERE deleted = 0 AND status = 'cancelled' "
      'AND event_date >= ? AND event_date < ?',
      args,
    )).first;

    final collected = (await d.rawQuery('''
      SELECT COALESCE(SUM(p.amount), 0) AS s
      FROM payments p JOIN bookings b ON b.id = p.booking_id
      WHERE b.deleted = 0 AND p.kind IN ('advance','balance')
        AND p.paid_at >= ? AND p.paid_at < ?
    ''', args)).first;

    final held = (await d.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN kind = 'deposit' THEN amount
                               WHEN kind = 'refund' THEN -amount ELSE 0 END), 0) AS s
      FROM payments p JOIN bookings b ON b.id = p.booking_id
      WHERE b.deleted = 0
    ''')).first;

    final items = await d.rawQuery('''
      SELECT bi.name AS name, COUNT(*) AS c, COALESCE(SUM(bi.taxable + bi.tax), 0) AS amt
      FROM booking_items bi JOIN bookings b ON b.id = bi.booking_id
      WHERE b.deleted = 0 AND b.status != 'cancelled'
        AND b.event_date >= ? AND b.event_date < ?
      GROUP BY bi.item_id ORDER BY amt DESC, c DESC LIMIT 5
    ''', args);

    final people = await d.rawQuery('''
      SELECT c.name AS name, COUNT(*) AS c, COALESCE(SUM(b.payable), 0) AS amt
      FROM bookings b JOIN customers c ON c.id = b.customer_id
      WHERE b.deleted = 0 AND b.status != 'cancelled'
        AND b.event_date >= ? AND b.event_date < ?
      GROUP BY b.customer_id ORDER BY amt DESC, c DESC LIMIT 5
    ''', args);

    final heldNow = n(held['s']);
    return ReportSummary(
      bookings: (totals['c'] as int?) ?? 0,
      cancelled: (cancelled['c'] as int?) ?? 0,
      billed: n(totals['billed']),
      tax: n(totals['tax']),
      collected: n(collected['s']),
      outstanding: n(totals['due']) < 0.005 ? 0 : n(totals['due']),
      depositsHeld: heldNow < 0.005 ? 0 : heldNow,
      topItems: [
        for (final i in items)
          ItemSales(i['name'] as String, i['c'] as int, n(i['amt'])),
      ],
      topCustomers: [
        for (final p in people)
          CustomerSales(p['name'] as String, p['c'] as int, n(p['amt'])),
      ],
    );
  }
}

final reportRepoProvider = Provider<ReportRepo>((_) => ReportRepo());

/// The span the Reports page is showing.
final reportRangeProvider = StateProvider.autoDispose<DateRange>(
  (_) => thisMonthRange(),
);

final reportSummaryProvider = FutureProvider.autoDispose<ReportSummary>(
  (ref) => ref.watch(reportRepoProvider).summary(ref.watch(reportRangeProvider)),
);
