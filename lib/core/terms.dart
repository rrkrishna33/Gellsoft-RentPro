import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/business_profile.dart';
import '../data/models.dart';
import '../l10n/strings.dart';
import 'constants.dart';

/// The words the app uses. They follow the kind of shop, so each owner sees
/// their own business:
/// - makeup artist: services, one appointment (date and time);
/// - vehicle / bike rental: vehicles, pickup and return (no event), rented by
///   the day or the hour;
/// - equipment / tools: equipment and units, usually by the day;
/// - costume, party decor and anything else: items for an event.
class Terms {
  const Terms(this.type);
  final ShopType type;

  /// A shop with nothing known yet reads as a rental shop.
  static const rental = Terms(ShopType.other);

  bool get service => type.isService;
  bool get vehicle => type == ShopType.vehicle;
  bool get equipment => type == ShopType.equipment;

  /// Whether the booking has an event date of its own. A vehicle is simply
  /// picked up and returned, so its event is its pickup day.
  bool get hasEvent => !vehicle;

  /// Whether the booking can carry a trial or fitting date (a dress is tried
  /// on before the event).
  bool get hasTrial => type == ShopType.costume;

  /// The rates a new item of this shop can be given, in the order shown. A
  /// vehicle is rented by the day or the hour, never "per event".
  List<RateType> get rateTypes => vehicle
      ? const [RateType.day, RateType.hour]
      : RateType.values;

  /// The rate a new item starts with: vehicles and tools are charged by the
  /// day, everything else once per event.
  RateType get defaultRateType =>
      vehicle || equipment ? RateType.day : RateType.event;

  String get items => switch (type) {
    ShopType.makeup => tr('Services'),
    ShopType.vehicle => tr('Vehicles'),
    ShopType.equipment => tr('Equipment'),
    _ => tr('Items'),
  };
  String get item => switch (type) {
    ShopType.makeup => tr('Service'),
    ShopType.vehicle => tr('Vehicle'),
    ShopType.equipment => tr('Equipment item'),
    _ => tr('Item'),
  };
  String get itemName => switch (type) {
    ShopType.makeup => tr('Service name'),
    ShopType.vehicle => tr('Vehicle name'),
    ShopType.equipment => tr('Equipment name'),
    _ => tr('Item name'),
  };
  String get addItem => switch (type) {
    ShopType.makeup => tr('Add service'),
    ShopType.vehicle => tr('Add vehicle'),
    ShopType.equipment => tr('Add equipment'),
    _ => tr('Add item'),
  };
  String get editItem => switch (type) {
    ShopType.makeup => tr('Edit service'),
    ShopType.vehicle => tr('Edit vehicle'),
    ShopType.equipment => tr('Edit equipment'),
    _ => tr('Edit item'),
  };
  String get chooseItems => switch (type) {
    ShopType.makeup => tr('Choose services'),
    ShopType.vehicle => tr('Choose vehicles'),
    ShopType.equipment => tr('Choose equipment'),
    _ => tr('Choose items'),
  };
  String get changeItems => switch (type) {
    ShopType.makeup => tr('Add or remove services'),
    ShopType.vehicle => tr('Add or remove vehicles'),
    ShopType.equipment => tr('Add or remove equipment'),
    _ => tr('Add or remove items'),
  };
  String get searchItems => switch (type) {
    ShopType.makeup => tr('Search services'),
    ShopType.vehicle => tr('Search vehicles'),
    ShopType.equipment => tr('Search equipment'),
    _ => tr('Search items'),
  };
  String get chooseOne => switch (type) {
    ShopType.makeup => tr('Choose at least one service.'),
    ShopType.vehicle => tr('Choose at least one vehicle.'),
    ShopType.equipment => tr('Choose at least one equipment item.'),
    _ => tr('Choose at least one item.'),
  };
  String get noItemsYet => switch (type) {
    ShopType.makeup => tr('Add the services you offer, with their price.'),
    ShopType.vehicle => tr('Add the vehicles you rent out, with their rate.'),
    ShopType.equipment => tr('Add the equipment you rent out, with its rate.'),
    _ => tr('Add the things you rent out, with their rate.'),
  };
  String get removeItemTitle => switch (type) {
    ShopType.makeup => tr('Remove this service?'),
    ShopType.vehicle => tr('Remove this vehicle?'),
    ShopType.equipment => tr('Remove this equipment?'),
    _ => tr('Remove this item?'),
  };
  String get eventDate => service ? tr('Appointment date') : tr('Event date');

  /// Item form: what the size, quantity, rent and deposit boxes are called.
  String get sizeLabel => switch (type) {
    ShopType.vehicle => tr('Model or registration no. (optional)'),
    ShopType.equipment => tr('Model or capacity (optional)'),
    _ => tr('Size (optional)'),
  };
  String get quantityHelp => switch (type) {
    ShopType.vehicle => tr('Vehicles you have'),
    ShopType.equipment => tr('Units you have'),
    _ => tr('Pieces you have'),
  };
  String get rentLabel => switch (type) {
    ShopType.vehicle => tr('Rent for one vehicle (₹)'),
    ShopType.equipment => tr('Rent for one unit (₹)'),
    _ => tr('Rent for one piece (₹)'),
  };
  String get depositLabel => switch (type) {
    ShopType.vehicle => tr('Deposit for one vehicle (₹)'),
    ShopType.equipment => tr('Deposit for one unit (₹)'),
    _ => tr('Deposit for one piece (₹)'),
  };

  /// Booking form: the reminder before the items go out.
  String get remindLabel => switch (type) {
    ShopType.makeup => tr('Remind me before the appointment'),
    ShopType.vehicle => tr('Remind me before pickup'),
    _ => tr('Remind me before the event'),
  };
}

final termsProvider = Provider<Terms>(
  (ref) => Terms(
    ref.watch(profileProvider).valueOrNull?.type ?? ShopType.other,
  ),
);
