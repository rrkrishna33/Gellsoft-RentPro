import '../l10n/strings.dart';

/// How an item is charged: one flat rate per booking ("event"), or per day.
enum RateType {
  event('Per event'),
  day('Per day');

  /// English wording; also the translation key (see `tr`).
  final String en;
  const RateType(this.en);

  String get label => tr(en);

  static RateType fromName(String? n) =>
      values.firstWhere((r) => r.name == n, orElse: () => RateType.event);
}

/// Whether an item can be booked.
enum ItemStatus {
  active('Available'),
  repair('In repair'),
  retired('Retired');

  final String en;
  const ItemStatus(this.en);

  String get label => tr(en);

  /// Only an available item can go on a new booking.
  bool get bookable => this == ItemStatus.active;

  static ItemStatus fromName(String? n) =>
      values.firstWhere((s) => s.name == n, orElse: () => ItemStatus.active);
}

/// Something the shop rents out.
class RentItem {
  final int? id;
  final String uuid;
  final String name;
  final String category;
  final String size;
  final RateType rateType;
  final double rate;
  final double deposit;
  final String notes;
  final ItemStatus status;
  final DateTime createdAt;

  const RentItem({
    this.id,
    this.uuid = '',
    required this.name,
    this.category = '',
    this.size = '',
    this.rateType = RateType.event,
    this.rate = 0,
    this.deposit = 0,
    this.notes = '',
    this.status = ItemStatus.active,
    required this.createdAt,
  });

  RentItem copyWith({
    String? name,
    String? category,
    String? size,
    RateType? rateType,
    double? rate,
    double? deposit,
    String? notes,
    ItemStatus? status,
  }) => RentItem(
    id: id,
    uuid: uuid,
    name: name ?? this.name,
    category: category ?? this.category,
    size: size ?? this.size,
    rateType: rateType ?? this.rateType,
    rate: rate ?? this.rate,
    deposit: deposit ?? this.deposit,
    notes: notes ?? this.notes,
    status: status ?? this.status,
    createdAt: createdAt,
  );

  factory RentItem.fromRow(Map<String, Object?> r) => RentItem(
    id: r['id'] as int,
    uuid: r['uuid'] as String,
    name: r['name'] as String,
    category: (r['category'] as String?) ?? '',
    size: (r['size'] as String?) ?? '',
    rateType: RateType.fromName(r['rate_type'] as String?),
    rate: (r['rate'] as num?)?.toDouble() ?? 0,
    deposit: (r['deposit'] as num?)?.toDouble() ?? 0,
    notes: (r['notes'] as String?) ?? '',
    status: ItemStatus.fromName(r['status'] as String?),
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
  );
}

/// A person who rents from the shop.
class Customer {
  final int? id;
  final String uuid;
  final String name;
  final String phone;
  final String address;

  /// A note about the ID the customer showed (for example "Aadhaar ending
  /// 1234"). The app never stores the ID itself.
  final String idNote;
  final String notes;
  final DateTime createdAt;

  const Customer({
    this.id,
    this.uuid = '',
    required this.name,
    this.phone = '',
    this.address = '',
    this.idNote = '',
    this.notes = '',
    required this.createdAt,
  });

  Customer copyWith({
    String? name,
    String? phone,
    String? address,
    String? idNote,
    String? notes,
  }) => Customer(
    id: id,
    uuid: uuid,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    address: address ?? this.address,
    idNote: idNote ?? this.idNote,
    notes: notes ?? this.notes,
    createdAt: createdAt,
  );

  factory Customer.fromRow(Map<String, Object?> r) => Customer(
    id: r['id'] as int,
    uuid: r['uuid'] as String,
    name: r['name'] as String,
    phone: (r['phone'] as String?) ?? '',
    address: (r['address'] as String?) ?? '',
    idNote: (r['id_note'] as String?) ?? '',
    notes: (r['notes'] as String?) ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
  );
}
