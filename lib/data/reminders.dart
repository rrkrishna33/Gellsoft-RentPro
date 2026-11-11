import '../core/format.dart';
import 'booking_models.dart';

/// What needs doing about a booking.
enum ReminderKind {
  /// The items must go out soon (or should have gone out already).
  sendItems,

  /// The items are due back today or tomorrow.
  returnDue,

  /// The items are out and past their return day.
  overdue,

  /// Rent is still to be collected.
  balance,
}

class ReminderItem {
  const ReminderItem(this.kind, this.booking, this.date);
  final ReminderKind kind;
  final Booking booking;

  /// The day that matters: pickup for [ReminderKind.sendItems], return for
  /// the return kinds, the event for [ReminderKind.balance].
  final DateTime date;

  /// Days from today (negative = already past).
  int daysAway(DateTime today) => dayOf(date).difference(dayOf(today)).inDays;
}

/// Works out what the owner has to do today, from the bookings that are still
/// open. The same rules drive the Reminders page, the Home badge and the
/// notifications, so they always agree.
///
/// - send items: a booked booking, from [Booking.remindDays] before its event
///   until its return day (so a late one keeps showing);
/// - return due: out, and due back today or tomorrow;
/// - overdue: out, and past its return day;
/// - balance: not cancelled, with rent still to collect, once the items are out
///   or back, or when they go out within a day.
List<ReminderItem> buildReminders(List<Booking> bookings, DateTime now) {
  final today = dayOf(now);
  final tomorrow = today.add(const Duration(days: 1));
  final out = <ReminderItem>[];
  for (final b in bookings) {
    switch (b.status) {
      case BookingStatus.booked:
        final from = b.eventDate.subtract(Duration(days: b.remindDays));
        if (!today.isBefore(from) && !today.isAfter(b.returnDate)) {
          out.add(ReminderItem(ReminderKind.sendItems, b, b.pickupDate));
        }
        if (b.balanceDue > 0 && !b.pickupDate.isAfter(tomorrow)) {
          out.add(ReminderItem(ReminderKind.balance, b, b.eventDate));
        }
      case BookingStatus.pickedUp:
        if (b.returnDate.isBefore(today)) {
          out.add(ReminderItem(ReminderKind.overdue, b, b.returnDate));
        } else if (!b.returnDate.isAfter(tomorrow)) {
          out.add(ReminderItem(ReminderKind.returnDue, b, b.returnDate));
        }
        if (b.balanceDue > 0) {
          out.add(ReminderItem(ReminderKind.balance, b, b.eventDate));
        }
      case BookingStatus.returned:
        if (b.balanceDue > 0) {
          out.add(ReminderItem(ReminderKind.balance, b, b.eventDate));
        }
      case BookingStatus.cancelled:
        break;
    }
  }
  int rank(ReminderKind k) => switch (k) {
    ReminderKind.overdue => 0,
    ReminderKind.returnDue => 1,
    ReminderKind.sendItems => 2,
    ReminderKind.balance => 3,
  };
  out.sort((a, c) {
    final r = rank(a.kind).compareTo(rank(c.kind));
    return r != 0 ? r : a.date.compareTo(c.date);
  });
  return out;
}

/// How many things need attention today (for the badge on Home).
int attentionCount(List<ReminderItem> items) => items.length;
