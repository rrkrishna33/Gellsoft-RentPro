import '../l10n/strings.dart';

/// How an item is charged: one flat rate per booking ("event"), or per day.
enum RateType {
  event('Per event'),
  day('Per day'),
  hour('Per hour');

  /// English wording; also the translation key (see `tr`).
  final String en;
  const RateType(this.en);

  String get label => tr(en);

  /// Charged by the hour: the booking needs a start and an end time.
  bool get isHourly => this == RateType.hour;

  static RateType fromName(String? n) =>
      values.firstWhere((r) => r.name == n, orElse: () => RateType.event);
}

/// Whether an item can be booked.
enum ItemStatus {
  active('Available'),
  repair('In repair'),
  cleaning('At cleaning'),
  retired('Retired');

  final String en;
  const ItemStatus(this.en);

  String get label => tr(en);

  /// Only an available item can go on a new booking.
  bool get bookable => this == ItemStatus.active;

  static ItemStatus fromName(String? n) =>
      values.firstWhere((s) => s.name == n, orElse: () => ItemStatus.active);
}

/// One picture of an item. [path] is a file in the app's photo folder.
class ItemPhoto {
  final int id;
  final int itemId;
  final String path;
  final int sort;

  const ItemPhoto({
    required this.id,
    required this.itemId,
    required this.path,
    this.sort = 0,
  });

  factory ItemPhoto.fromRow(Map<String, Object?> r) => ItemPhoto(
    id: r['id'] as int,
    itemId: r['item_id'] as int,
    path: r['path'] as String,
    sort: (r['sort'] as int?) ?? 0,
  );
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

  /// SAC/HSN code printed on the invoice (rental of goods is 9973).
  final String hsn;

  /// GST rate in percent charged on this item's rent.
  final double gstRate;

  /// How many of this item the shop has (a shop with ten chairs has one item
  /// "Chair" with a quantity of 10). Never less than 1.
  final int quantity;

  /// The least hours this item is charged for when it is rented by the hour
  /// (a 30 minute use still pays for [minHours]). At least 1.
  final int minHours;

  /// Hours the item stays blocked after each return (cleaning, servicing).
  final int bufferHours;

  /// Rate for a whole week and for a 30-day month, for an item rented by the
  /// day. 0 means no such rate.
  final double weekRate;
  final double monthRate;

  /// What a late return costs for each late hour (an item rented by the hour)
  /// or day. 0 means the shop has not set a rate.
  final double lateFee;

  /// When an item that is in repair or at cleaning is back in service. Null
  /// means no date is known, so it stays out until the shop changes it.
  final DateTime? statusUntil;
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
    this.hsn = '',
    this.gstRate = 0,
    this.quantity = 1,
    this.minHours = 1,
    this.bufferHours = 0,
    this.weekRate = 0,
    this.monthRate = 0,
    this.lateFee = 0,
    this.statusUntil,
    this.notes = '',
    this.status = ItemStatus.active,
    required this.createdAt,
  });

  /// Whether the item can go on a booking that starts on [day]: it is
  /// available, or it is out of service only until a date that has passed by
  /// then.
  bool bookableOn(DateTime day) {
    if (status.bookable) return true;
    if (status == ItemStatus.retired) return false;
    final until = statusUntil;
    return until != null && !DateTime(day.year, day.month, day.day).isBefore(until);
  }

  RentItem copyWith({
    String? name,
    String? category,
    String? size,
    RateType? rateType,
    double? rate,
    double? deposit,
    String? hsn,
    double? gstRate,
    int? quantity,
    int? minHours,
    int? bufferHours,
    double? weekRate,
    double? monthRate,
    double? lateFee,
    DateTime? statusUntil,
    bool clearStatusUntil = false,
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
    hsn: hsn ?? this.hsn,
    gstRate: gstRate ?? this.gstRate,
    quantity: quantity ?? this.quantity,
    minHours: minHours ?? this.minHours,
    bufferHours: bufferHours ?? this.bufferHours,
    weekRate: weekRate ?? this.weekRate,
    monthRate: monthRate ?? this.monthRate,
    lateFee: lateFee ?? this.lateFee,
    statusUntil: clearStatusUntil ? null : (statusUntil ?? this.statusUntil),
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
    hsn: (r['hsn'] as String?) ?? '',
    gstRate: (r['gst_rate'] as num?)?.toDouble() ?? 0,
    quantity: ((r['quantity'] as num?)?.toInt() ?? 1).clamp(1, 1 << 30),
    minHours: ((r['min_hours'] as num?)?.toInt() ?? 1).clamp(1, 1 << 30),
    bufferHours: ((r['buffer_hours'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30),
    weekRate: (r['week_rate'] as num?)?.toDouble() ?? 0,
    monthRate: (r['month_rate'] as num?)?.toDouble() ?? 0,
    lateFee: (r['late_fee'] as num?)?.toDouble() ?? 0,
    statusUntil: r['status_until'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r['status_until'] as int),
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

  /// The customer's GSTIN, when they have one (for a B2B invoice).
  final String gstin;

  /// Two-digit GST state code of where the customer is. Empty = same state
  /// as the shop.
  final String stateCode;

  /// A note about the ID the customer showed (for example "Aadhaar ending
  /// 1234"). The app never stores the ID itself.
  final String idNote;
  final String notes;

  /// A warning staff should see when this customer books (for example
  /// "returned late twice"). Empty means none.
  final String warning;
  final DateTime createdAt;

  const Customer({
    this.id,
    this.uuid = '',
    required this.name,
    this.phone = '',
    this.address = '',
    this.gstin = '',
    this.stateCode = '',
    this.idNote = '',
    this.notes = '',
    this.warning = '',
    required this.createdAt,
  });

  Customer copyWith({
    String? name,
    String? phone,
    String? address,
    String? gstin,
    String? stateCode,
    String? idNote,
    String? notes,
    String? warning,
  }) => Customer(
    id: id,
    uuid: uuid,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    address: address ?? this.address,
    gstin: gstin ?? this.gstin,
    stateCode: stateCode ?? this.stateCode,
    idNote: idNote ?? this.idNote,
    notes: notes ?? this.notes,
    warning: warning ?? this.warning,
    createdAt: createdAt,
  );

  factory Customer.fromRow(Map<String, Object?> r) => Customer(
    id: r['id'] as int,
    uuid: r['uuid'] as String,
    name: r['name'] as String,
    phone: (r['phone'] as String?) ?? '',
    address: (r['address'] as String?) ?? '',
    gstin: (r['gstin'] as String?) ?? '',
    stateCode: (r['state_code'] as String?) ?? '',
    idNote: (r['id_note'] as String?) ?? '',
    notes: (r['notes'] as String?) ?? '',
    warning: (r['warning'] as String?) ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
  );
}

/// One entry in an item's repair and damage log.
class ItemRepair {
  const ItemRepair({
    required this.id,
    required this.itemId,
    required this.at,
    this.bookingId,
    this.note = '',
    this.cost = 0,
  });
  final int id;
  final int itemId;
  final int? bookingId;
  final String note;
  final double cost;
  final DateTime at;

  factory ItemRepair.fromRow(Map<String, Object?> r) => ItemRepair(
    id: r['id'] as int,
    itemId: r['item_id'] as int,
    bookingId: r['booking_id'] as int?,
    note: (r['note'] as String?) ?? '',
    cost: (r['cost'] as num?)?.toDouble() ?? 0,
    at: DateTime.fromMillisecondsSinceEpoch(r['at'] as int),
  );
}
