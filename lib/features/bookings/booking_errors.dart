import '../../data/booking_repo.dart';
import '../../l10n/strings.dart';

/// What to tell the user when a booking could not be saved or changed.
String bookingErrorText(BookingException e) => switch (e.error) {
  BookingError.limitReached => tr('The free limit has been reached.'),
  BookingError.itemBusy => tr('{item} is already booked for some of these days.', {
    'item': e.detail,
  }),
  BookingError.badDates => tr(
    'The dates must go in order: pickup, then the event, then return.',
  ),
  BookingError.noItems => tr('Choose at least one item.'),
  BookingError.itemUnavailable => tr('{item} cannot be booked right now.', {
    'item': e.detail,
  }),
  BookingError.badState => tr('This booking cannot be changed any more.'),
  BookingError.badAmount => tr('That amount is not allowed.'),
  BookingError.badDiscount => tr('The discount cannot be more than the rent.'),
};
