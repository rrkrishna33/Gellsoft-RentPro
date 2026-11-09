import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

/// The shop: its name, what it rents and how to reach it. Shown on receipts.
class BusinessProfile {
  final String name;
  final ShopType type;
  final String phone;
  final String address;

  /// How many days before the event the shop wants the "send the items"
  /// reminder (the default for each new booking).
  final int remindDays;

  const BusinessProfile({
    required this.name,
    required this.type,
    this.phone = '',
    this.address = '',
    this.remindDays = 2,
  });

  BusinessProfile copyWith({
    String? name,
    ShopType? type,
    String? phone,
    String? address,
    int? remindDays,
  }) => BusinessProfile(
    name: name ?? this.name,
    type: type ?? this.type,
    phone: phone ?? this.phone,
    address: address ?? this.address,
    remindDays: remindDays ?? this.remindDays,
  );

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('b_name', name);
    await sp.setString('b_type', type.name);
    await sp.setString('b_phone', phone);
    await sp.setString('b_address', address);
    await sp.setInt('b_remind', remindDays);
  }

  static Future<BusinessProfile?> load() async {
    final sp = await SharedPreferences.getInstance();
    final name = sp.getString('b_name');
    if (name == null) return null;
    return BusinessProfile(
      name: name,
      type: ShopType.values.firstWhere(
        (t) => t.name == sp.getString('b_type'),
        orElse: () => ShopType.other,
      ),
      phone: sp.getString('b_phone') ?? '',
      address: sp.getString('b_address') ?? '',
      remindDays: sp.getInt('b_remind') ?? 2,
    );
  }
}

class ProfileNotifier extends AsyncNotifier<BusinessProfile?> {
  @override
  Future<BusinessProfile?> build() => BusinessProfile.load();

  Future<void> saveProfile(BusinessProfile p) async {
    await p.save();
    state = AsyncData(p);
  }
}

final profileProvider =
    AsyncNotifierProvider<ProfileNotifier, BusinessProfile?>(
      ProfileNotifier.new,
    );
