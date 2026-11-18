import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ids.dart';
import '../subscription/plan.dart';
import 'booking_repo.dart' show BookingError, BookingException;
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
      'hsn': item.hsn.trim(),
      'gst_rate': item.gstRate,
      'quantity': item.quantity < 1 ? 1 : item.quantity,
      'min_hours': item.minHours < 1 ? 1 : item.minHours,
      'buffer_hours': item.bufferHours < 0 ? 0 : item.bufferHours,
      'week_rate': item.weekRate < 0 ? 0 : item.weekRate,
      'month_rate': item.monthRate < 0 ? 0 : item.monthRate,
      'late_fee': item.lateFee < 0 ? 0 : item.lateFee,
      'status_until': item.statusUntil == null ||
              item.status.bookable ||
              item.status == ItemStatus.retired
          ? null
          : DateTime(
              item.statusUntil!.year,
              item.statusUntil!.month,
              item.statusUntil!.day,
            ).millisecondsSinceEpoch,
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

  /// The pictures of one item, the cover first.
  Future<List<ItemPhoto>> photosOf(int itemId) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.query(
      'item_photos',
      where: 'item_id = ?',
      whereArgs: [itemId],
      orderBy: 'sort, id',
    );
    return rows.map(ItemPhoto.fromRow).toList();
  }

  /// The cover picture of every item that has one (item id to file path), for
  /// lists. One query, not one per item.
  Future<Map<int, String>> covers() async {
    final d = await AppDatabase.instance.db;
    final rows = await d.rawQuery('''
      SELECT p.item_id AS item_id, p.path AS path
      FROM item_photos p
      WHERE p.id = (SELECT q.id FROM item_photos q WHERE q.item_id = p.item_id
                    ORDER BY q.sort, q.id LIMIT 1)
    ''');
    return {for (final r in rows) r['item_id'] as int: r['path'] as String};
  }

  /// Adds a picture (a file already saved in the app's folder) at the end.
  /// The free plan keeps [FreePlan.photosPerItem]; Pro keeps
  /// [proPhotosPerItem]. Returns the new picture's id.
  Future<int> addPhoto(int itemId, String path, {required bool isPro}) async {
    final d = await AppDatabase.instance.db;
    return d.transaction((txn) async {
      final n = (await txn.rawQuery(
        'SELECT COUNT(*) AS n, COALESCE(MAX(sort), -1) AS top FROM item_photos WHERE item_id = ?',
        [itemId],
      )).first;
      final limit = isPro ? proPhotosPerItem : FreePlan.photosPerItem;
      if ((n['n'] as int) >= limit) {
        throw const BookingException(BookingError.limitReached);
      }
      return txn.insert('item_photos', {
        'item_id': itemId,
        'path': path,
        'sort': (n['top'] as int) + 1,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  /// Takes a picture off an item. Returns its file path so the caller can
  /// delete the file, or null if there was no such picture.
  Future<String?> removePhoto(int photoId) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.query('item_photos', where: 'id = ?', whereArgs: [photoId]);
    if (rows.isEmpty) return null;
    await d.delete('item_photos', where: 'id = ?', whereArgs: [photoId]);
    return rows.first['path'] as String;
  }

  /// Puts the pictures of an item in the given order (the first becomes the
  /// cover). Pictures not listed keep their place after the listed ones.
  Future<void> setPhotoOrder(int itemId, List<int> ids) async {
    final d = await AppDatabase.instance.db;
    await d.transaction((txn) async {
      for (var i = 0; i < ids.length; i++) {
        await txn.update(
          'item_photos',
          {'sort': i},
          where: 'id = ? AND item_id = ?',
          whereArgs: [ids[i], itemId],
        );
      }
      await txn.rawUpdate(
        'UPDATE item_photos SET sort = sort + ? WHERE item_id = ? AND id NOT IN (${ids.isEmpty ? '0' : ids.join(',')})',
        [ids.length, itemId],
      );
    });
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

extension ItemRepairs on ItemRepo {
  /// The repair and damage log of an item, newest first.
  Future<List<ItemRepair>> repairsOf(int itemId) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.query(
      'item_repairs',
      where: 'item_id = ?',
      whereArgs: [itemId],
      orderBy: 'at DESC, id DESC',
    );
    return rows.map(ItemRepair.fromRow).toList();
  }

  /// Adds an entry to the log. [cost] is what putting it right cost the shop.
  Future<int> addRepair(
    int itemId, {
    required DateTime at,
    String note = '',
    double cost = 0,
    int? bookingId,
  }) async {
    final d = await AppDatabase.instance.db;
    return d.insert('item_repairs', {
      'item_id': itemId,
      'booking_id': bookingId,
      'note': note.trim(),
      'cost': cost < 0 ? 0 : cost,
      'at': DateTime(at.year, at.month, at.day).millisecondsSinceEpoch,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> removeRepair(int id) async {
    final d = await AppDatabase.instance.db;
    await d.delete('item_repairs', where: 'id = ?', whereArgs: [id]);
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
      'gstin': c.gstin.trim().toUpperCase(),
      'state_code': c.stateCode.trim(),
      'id_note': c.idNote.trim(),
      'notes': c.notes.trim(),
      'warning': c.warning.trim(),
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

/// The cover picture of every item that has one (item id to file path).
final itemCoversProvider = FutureProvider.autoDispose<Map<int, String>>(
  (ref) => ref.watch(itemRepoProvider).covers(),
);

final customersProvider = FutureProvider.autoDispose<List<Customer>>((ref) {
  final q = ref.watch(customerSearchProvider);
  return ref.watch(customerRepoProvider).list(query: q);
});
