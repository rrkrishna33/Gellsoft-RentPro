import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/business_profile.dart';
import '../l10n/strings.dart';

/// The words the app uses, which differ for a service business (a makeup
/// artist books services for an appointment) and a rental shop (items go out
/// and come back).
class Terms {
  const Terms(this.service);
  final bool service;

  /// A shop with nothing known yet reads as a rental shop.
  static const rental = Terms(false);

  String get items => service ? tr('Services') : tr('Items');
  String get item => service ? tr('Service') : tr('Item');
  String get itemName => service ? tr('Service name') : tr('Item name');
  String get addItem => service ? tr('Add service') : tr('Add item');
  String get editItem => service ? tr('Edit service') : tr('Edit item');
  String get chooseItems => service ? tr('Choose services') : tr('Choose items');
  String get changeItems =>
      service ? tr('Add or remove services') : tr('Add or remove items');
  String get searchItems => service ? tr('Search services') : tr('Search items');
  String get chooseOne =>
      service ? tr('Choose at least one service.') : tr('Choose at least one item.');
  String get noItemsYet => service
      ? tr('Add the services you offer, with their price.')
      : tr('Add the things you rent out, with their rate.');
  String get removeItemTitle =>
      service ? tr('Remove this service?') : tr('Remove this item?');
  String get eventDate => service ? tr('Appointment date') : tr('Event date');
}

final termsProvider = Provider<Terms>(
  (ref) => Terms(
    ref.watch(profileProvider).valueOrNull?.type.isService ?? false,
  ),
);
