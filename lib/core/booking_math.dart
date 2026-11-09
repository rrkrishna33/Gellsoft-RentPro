import '../data/models.dart';
import 'format.dart';

/// How many calendar days the items are away, counting both the pickup day
/// and the return day (pick up Monday, return Wednesday = 3 days).
int rentalDays(DateTime pickup, DateTime ret) {
  final a = DateTime.utc(pickup.year, pickup.month, pickup.day);
  final b = DateTime.utc(ret.year, ret.month, ret.day);
  final days = b.difference(a).inDays + 1;
  return days < 1 ? 1 : days;
}

/// What one item costs for a booking: its flat rate, or its daily rate times
/// the days away.
double lineAmount(RateType type, double rate, DateTime pickup, DateTime ret) =>
    type == RateType.day ? rate * rentalDays(pickup, ret) : rate;

/// Whether two bookings of the same item clash: their day ranges (pickup to
/// return, both included) share at least one day.
bool rangesOverlap(DateTime aFrom, DateTime aTo, DateTime bFrom, DateTime bTo) {
  final af = dayOf(aFrom), at = dayOf(aTo), bf = dayOf(bFrom), bt = dayOf(bTo);
  return !af.isAfter(bt) && !bf.isAfter(at);
}
