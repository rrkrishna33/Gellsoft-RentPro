import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import 'database.dart';

/// The numbers on Home.
class DashboardCounts {
  final int pickupsToday;
  final int returnsToday;
  final int overdueReturns;
  final int eventsThisWeek;

  /// Rent still to collect on bookings that are not cancelled.
  final double balanceDue;

  /// Rent taken this calendar month (advance and balance payments).
  final double collectedThisMonth;

  const DashboardCounts({
    this.pickupsToday = 0,
    this.returnsToday = 0,
    this.overdueReturns = 0,
    this.eventsThisWeek = 0,
    this.balanceDue = 0,
    this.collectedThisMonth = 0,
  });
}

class DashboardRepo {
  Future<DashboardCounts> counts([DateTime? now]) async {
    final d = await AppDatabase.instance.db;
    final today = dayOf(now ?? DateTime.now());
    final t = today.millisecondsSinceEpoch;
    final weekEnd = DateTime(
      today.year,
      today.month,
      today.day + 6,
    ).millisecondsSinceEpoch;
    final month = monthStart(today).millisecondsSinceEpoch;
    final nextMonth = DateTime(today.year, today.month + 1).millisecondsSinceEpoch;

    Future<int> count(String where, List<Object?> args) async {
      final r = await d.rawQuery(
        'SELECT COUNT(*) AS n FROM bookings WHERE deleted = 0 AND $where',
        args,
      );
      return (r.first['n'] as int?) ?? 0;
    }

    final due = await d.rawQuery('''
      SELECT COALESCE(SUM(b.payable - COALESCE((
        SELECT SUM(p.amount) FROM payments p
        WHERE p.booking_id = b.id AND p.kind IN ('advance', 'balance')), 0)), 0)
        AS due
      FROM bookings b
      WHERE b.deleted = 0 AND b.status != 'cancelled'
    ''');
    final taken = await d.rawQuery(
      '''
      SELECT COALESCE(SUM(p.amount), 0) AS sum
      FROM payments p JOIN bookings b ON b.id = p.booking_id
      WHERE b.deleted = 0 AND p.kind IN ('advance', 'balance')
        AND p.paid_at >= ? AND p.paid_at < ?
    ''',
      [month, nextMonth],
    );

    return DashboardCounts(
      pickupsToday: await count("status = 'booked' AND pickup_date = ?", [t]),
      returnsToday: await count(
        "status = 'picked_up' AND return_date = ?",
        [t],
      ),
      overdueReturns: await count(
        "status = 'picked_up' AND return_date < ?",
        [t],
      ),
      eventsThisWeek: await count(
        "status IN ('booked', 'picked_up') AND event_date >= ? AND event_date <= ?",
        [t, weekEnd],
      ),
      balanceDue: (due.first['due'] as num?)?.toDouble() ?? 0,
      collectedThisMonth: (taken.first['sum'] as num?)?.toDouble() ?? 0,
    );
  }
}

final dashboardRepoProvider = Provider<DashboardRepo>((_) => DashboardRepo());

final dashboardProvider = FutureProvider.autoDispose<DashboardCounts>(
  (ref) => ref.watch(dashboardRepoProvider).counts(),
);
