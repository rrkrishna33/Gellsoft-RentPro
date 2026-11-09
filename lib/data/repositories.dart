import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ids.dart';
import 'database.dart';
import 'models.dart';

/// Escapes `%`, `_` and `\` so a search for "50%" finds "50%" and not "50x".
String _like(String q) => q
    .replaceAll(r'\', r'\\')
    .replaceAll('%', r'\%')
    .replaceAll('_', r'\_');

class ItemRepo {
  /// Items, newest first within each category. [query] matches the name,
  /// category or size. Retired items are hidden unless [includeRetired].
  Future<List<RentItem>> list({
    String query = '',
    bool includeRetired = false,
  }) async {
    final d = await AppDatabase.instance.db;
    final where = StringBuffer('deleted = 0');
    final args = <Object?>[];
    if (!includeRetired) where.write(" AND status != 'retired'");
    final q = query.trim();
    if (q.isNotEmpty) {
      where.write(
        " AND (name LIKE ? ESCAPE '\\' OR category LIKE ? ESCAPE '\\'"
        " OR size LIKE ? ESCAPE '\\')",
      );
      final like = '%${_like(q)}%';
      args.addAll([like, like, like]);
    }
    final rows = await d.query(
      'items',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'category COLLATE NOCASE, name COLLATE NOCASE',
    );
    return rows.map(RentItem.fromRow).toList();
  }

  Future<RentItem?> get(int id) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.query(
      'items',
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : RentItem.fromRow(rows.first);
  }

  /// Saves a new item (no id) or changes an existing one. Returns the id.
  Future<int> save(RentItem item) async {
    final d = await AppDatabase.instance.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final values = <String, Object?>{
      'name': item.name.trim(),
      'category': item.category.trim(),
      'size': item.size.trim(),
      'rate_type': item.rateType.name,
      'rate': item.rate,
      'deposit': item.deposit,
      'notes': item.notes.trim(),
      'status': item.status.name,
      'updated_at': now,
    };
    final id = item.id;
    if (id == null) {
      return d.insert('items', {
        ...values,
        'uuid': item.uuid.isEmpty ? newUuid() : item.uuid,
        'created_at': now,
      });
    }
    await d.update('items', values, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Future<void> setStatus(int id, ItemStatus status) async {
    final d = await AppDatabase.instance.db;
    await d.update(
      'items',
      {'status': status.name, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Removes an item from every list. Bookings that already used it keep its
  /// name and rate, so history is never lost.
  Future<void> delete(int id) async {
    final d = await AppDatabase.instance.db;
    await d.update(
      'items',
      {'deleted': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// The categories already in use, so the form can offer them again.
  Future<List<String>> categoriesInUse() async {
    final d = await AppDatabase.instance.db;
    final rows = await d.rawQuery(
      "SELECT DISTINCT category FROM items WHERE deleted = 0 AND category != '' "
      'ORDER BY category COLLATE NOCASE',
    );
    return [for (final r in rows) r['category'] as String];
  }
}

class CustomerRepo {
  /// Customers by name. [query] matches the name, phone or address.
  Future<List<Customer>> list({String query = ''}) async {
    final d = await AppDatabase.instance.db;
    final where = StringBuffer('deleted = 0');
    final args = <Object?>[];
    final q = query.trim();
    if (q.isNotEmpty) {
      where.write(
        " AND (name LIKE ? ESCAPE '\\' OR phone LIKE ? ESCAPE '\\'"
        " OR address LIKE ? ESCAPE '\\')",
      );
      final like = '%${_like(q)}%';
      args.addAll([like, like, like]);
    }
    final rows = await d.query(
      'customers',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Customer.fromRow).toList();
  }

  Future<Customer?> get(int id) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.query(
      'customers',
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : Customer.fromRow(rows.first);
  }

  /// A customer with this phone number, if the shop already has one. Used to
  /// warn before adding the same person twice. [exceptId] skips the customer
  /// being edited.
  Future<Customer?> byPhone(String phone, {int? exceptId}) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) return null;
    final d = await AppDatabase.instance.db;
    final rows = await d.query(
      'customers',
      where: "deleted = 0 AND phone != ''",
    );
    for (final r in rows) {
      if (r['id'] == exceptId) continue;
      final other = (r['phone'] as String).replaceAll(RegExp(r'\D'), '');
      if (other == digits) return Customer.fromRow(r);
    }
    return null;
  }

  Future<int> save(Customer c) async {
    final d = await AppDatabase.instance.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final values = <String, Object?>{
      'name': c.name.trim(),
      'phone': c.phone.trim(),
      'address': c.address.trim(),
      'id_note': c.idNote.trim(),
      'notes': c.notes.trim(),
      'updated_at': now,
    };
    final id = c.id;
    if (id == null) {
      return d.insert('customers', {
        ...values,
        'uuid': c.uuid.isEmpty ? newUuid() : c.uuid,
        'created_at': now,
      });
    }
    await d.update('customers', values, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  /// Removes a customer from the list. Their bookings keep working.
  Future<void> delete(int id) async {
    final d = await AppDatabase.instance.db;
    await d.update(
      'customers',
      {'deleted': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

final itemRepoProvider = Provider<ItemRepo>((_) => ItemRepo());
final customerRepoProvider = Provider<CustomerRepo>((_) => CustomerRepo());

/// What the search box on each list currently holds.
final itemSearchProvider = StateProvider.autoDispose<String>((_) => '');
final customerSearchProvider = StateProvider.autoDispose<String>((_) => '');

final itemsProvider = FutureProvider.autoDispose<List<RentItem>>((ref) {
  final q = ref.watch(itemSearchProvider);
  return ref.watch(itemRepoProvider).list(query: q);
});

final customersProvider = FutureProvider.autoDispose<List<Customer>>((ref) {
  final q = ref.watch(customerSearchProvider);
  return ref.watch(customerRepoProvider).list(query: q);
});
