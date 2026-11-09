import '../l10n/strings.dart';

/// What the free plan allows, and what needs Pro. The limits live here only,
/// so changing one is a one-line edit and every screen follows.
class FreePlan {
  /// New bookings a shop may create in one calendar month before Pro is
  /// needed. Existing bookings stay fully usable.
  static const bookingsPerMonth = 12;

  /// Photos kept on one booking (pickup and return together).
  static const photosPerBooking = 2;
}

/// Things that need Pro. `label` is shown on the Pro prompt.
enum ProFeature {
  unlimitedBookings('Unlimited bookings every month'),
  unlimitedPhotos('Unlimited photos on every booking'),
  notifications('Daily and custom reminder notifications');

  /// English wording; also the translation key (see `tr`).
  final String en;
  const ProFeature(this.en);

  String get label => tr(en);
}
