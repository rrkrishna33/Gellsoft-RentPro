import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'database.dart';

/// The shops on this phone. Each shop is kept completely apart from the
/// others: its own database file (items, customers, bookings, invoices, staff)
/// and its own shop details. The first shop is `main` and keeps the names the
/// app has always used, so nothing changes for a phone with one shop.
///
/// Which shop is open is remembered; the app restarts its screens when the
/// shop changes (see `switchShop`), so every screen reads the new one.
class Shops {
  Shops._();

  static const mainId = 'main';

  /// A shop added later: `s2`, `s3` and so on.
  static final _idPattern = RegExp(r'^s\d{1,3}$');

  static const _idsKey = 's_shopids';
  static const _activeKey = 's_activeshop';

  /// The shop that is open now.
  static String activeId = mainId;

  /// Shops added after the first.
  static List<String> extraIds = [];

  static List<String> get all => [mainId, ...extraIds];

  static bool isValidId(String id) => id == mainId || _idPattern.hasMatch(id);

  /// Reads the list of shops and the open one. Call at startup, and again
  /// after a backup is restored.
  static Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    extraIds = [
      for (final id in sp.getStringList(_idsKey) ?? const <String>[])
        if (_idPattern.hasMatch(id)) id,
    ];
    final open = sp.getString(_activeKey) ?? mainId;
    activeId = all.contains(open) ? open : mainId;
  }

  /// The name of a saved setting for a shop: `b_name` for the first shop,
  /// `b_s2_name` for the second. [prefix] is the group letter (`b` shop
  /// details, `s` app settings).
  static String key(String prefix, String name, {String? shop}) {
    final id = shop ?? activeId;
    return id == mainId ? '${prefix}_$name' : '${prefix}_${id}_$name';
  }

  /// The database file name of a shop.
  static String dbName(String id) =>
      id == mainId ? 'gellsoft_rentpro.db' : 'gellsoft_rentpro_$id.db';


  /// Adds a shop and returns its id. The shop is not opened.
  static Future<String> create() async {
    var n = 2;
    while (extraIds.contains('s$n')) {
      n++;
    }
    final id = 's$n';
    extraIds = [...extraIds, id];
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_idsKey, extraIds);
    return id;
  }

  /// Makes [id] the open shop: closes the open database so the next use opens
  /// that shop's file.
  static Future<void> activate(String id) async {
    if (!all.contains(id)) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_activeKey, id);
    activeId = id;
    await AppDatabase.instance.close();
  }

  /// Deletes a shop added later, with its data. The first shop cannot be
  /// deleted. If it was open, the first shop opens instead.
  static Future<void> remove(String id) async {
    if (id == mainId || !extraIds.contains(id)) return;
    final wasOpen = activeId == id;
    if (wasOpen) await activate(mainId);
    extraIds = [for (final e in extraIds) if (e != id) e];
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_idsKey, extraIds);
    final mine = '_${id}_';
    for (final k in sp.getKeys().toList()) {
      if (k.length > 2 && k.substring(1).startsWith(mine)) await sp.remove(k);
    }
    await deleteDatabase(await AppDatabase.instance.pathFor(id));
  }

  /// Forgets everything (tests).
  static void resetForTests() {
    activeId = mainId;
    extraIds = [];
  }
}
