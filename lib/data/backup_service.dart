import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'database.dart';
import 'photo_store.dart';
import 'shops.dart';

/// A backup is one JSON file: the SQLite database of every shop (base64), the
/// booking photos and shop logos (base64, by file name) and the preferences
/// (shop details, GST and reminder settings).
///
/// `db` is the first shop; `shopDbs` holds any other shops by id. Who may sign
/// in (staff logins) stays on the phone and is never restored from a backup:
/// a backup must not bring back old PINs.
class BackupService {
  static const _format = 'gellsoft_rentpro_backup';

  /// Preferences that stay on this phone and are never exported or imported.
  static const lastBackupKey = 'last_backup';
  static const _deviceOnly = {
    lastBackupKey,
    // who is signed in to Google stays signed in after a restore
    'acct_email',
    'acct_name',
    // whether hiding amounts is on is a choice of this phone
    's_hideamounts',
    // which shop is open, and the PIN guess counter, belong to this phone
    's_activeshop',
    's_fail',
    's_lockuntil',
  };

  /// The recovery code of a shop's Admin stays with the people on this phone.
  static final _recoveryKey = RegExp(r'^s_(s\d{1,3}_)?recov(hash|salt)$');

  static bool _isDeviceOnly(String k) =>
      _deviceOnly.contains(k) || _recoveryKey.hasMatch(k);

  static final _sqliteHeader = ascii.encode('SQLite format 3');

  /// Far more than any shop's data; stops a hostile file from exhausting memory.
  static const maxBackupBytes = 600 * 1024 * 1024;

  /// Settings a backup may carry: only this app's own preference names.
  static final _allowedPrefKey = RegExp(r'^[bpsn]_[a-z0-9_]{1,40}$');

  /// A photo file name we wrote ourselves (a uuid and an image extension).
  static final _photoName = RegExp(r'^[A-Za-z0-9-]{8,64}\.(jpg|jpeg|png|webp|heic)$');

  /// Columns the app's own queries rely on, per table.
  static const _requiredColumns = <String, Set<String>>{
    'items': {'uuid', 'name', 'rate_type', 'rate', 'deposit', 'gst_rate', 'status', 'deleted'},
    'customers': {'uuid', 'name', 'phone', 'gstin', 'state_code', 'deleted'},
    'bookings': {
      'uuid',
      'number',
      'customer_id',
      'event_date',
      'pickup_date',
      'return_date',
      'status',
      'rent_total',
      'tax_total',
      'payable',
      'deleted',
    },
    'booking_items': {'booking_id', 'item_id', 'name', 'rate', 'amount', 'taxable', 'tax'},
    'payments': {'booking_id', 'kind', 'amount', 'mode', 'paid_at'},
    'booking_photos': {'booking_id', 'stage', 'path', 'created_at'},
    'invoices': {'uuid', 'booking_id', 'number', 'invoice_date', 'status', 'total', 'deleted'},
    'invoice_items': {'invoice_id', 'name', 'taxable', 'total'},
  };

  static FormatException get _invalidData =>
      const FormatException('The backup does not contain valid data');

  /// Opens the backup's database in a scratch file and checks it is intact,
  /// has this app's tables and columns, and carries nothing hidden (triggers
  /// or views). Throws [FormatException] otherwise. The live data is not
  /// touched.
  static Future<void> _checkDatabase(Uint8List bytes) async {
    final dir = p.dirname(await AppDatabase.instance.filePath);
    final scratch = File(p.join(dir, 'restore_check.db'));
    Database? db;
    try {
      await scratch.writeAsBytes(bytes, flush: true);
      db = await openDatabase(
        scratch.path,
        readOnly: true,
        singleInstance: false,
      );

      final integrity = await db.rawQuery('PRAGMA integrity_check');
      if (integrity.length != 1 || integrity.first.values.first != 'ok') {
        throw _invalidData;
      }
      final version =
          Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')) ?? 0;
      if (version < 1 || version > AppDatabase.schemaVersion) {
        throw const FormatException(
          'This backup is from a different version of the app',
        );
      }

      final objects = await db.rawQuery(
        "SELECT type, name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
      );
      if (objects.any((o) => o['type'] == 'trigger' || o['type'] == 'view')) {
        throw _invalidData;
      }

      for (final e in _requiredColumns.entries) {
        final cols = (await db.rawQuery(
          'PRAGMA table_info(${e.key})',
        )).map((r) => r['name'] as String).toSet();
        if (!cols.containsAll(e.value)) throw _invalidData;
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw _invalidData;
    } finally {
      await db?.close();
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final f = File('${scratch.path}$suffix');
        if (f.existsSync()) f.deleteSync();
      }
    }
  }

  static String suggestedName() {
    final n = DateTime.now();
    String t(int v) => v.toString().padLeft(2, '0');
    return 'gellsoft_rentpro_backup_${n.year}${t(n.month)}${t(n.day)}_${t(n.hour)}${t(n.minute)}.json';
  }

  /// The photo files a shop's bookings point to, by path. [id] may be a shop
  /// that is not open: its file is read on a connection of its own.
  static Future<List<String>> _photoPaths(String id) async {
    final path = await AppDatabase.instance.pathFor(id);
    if (!File(path).existsSync()) return const [];
    if (id == Shops.activeId) {
      final db = await AppDatabase.instance.db;
      return [
        for (final r in await db.query('booking_photos', columns: ['path']))
          r['path'] as String,
      ];
    }
    final db = await openDatabase(path, readOnly: true, singleInstance: false);
    try {
      return [
        for (final r in await db.query('booking_photos', columns: ['path']))
          r['path'] as String,
      ];
    } catch (_) {
      return const []; // a file without that table has no photos
    } finally {
      await db.close();
    }
  }

  /// Everything in one file: every shop's database, the photos and logos they
  /// use, and the settings.
  static Future<Uint8List> create() async {
    final open = await AppDatabase.instance.db;
    try {
      await open.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // Not in WAL mode; nothing to flush.
    }
    final files = <String, Uint8List>{};
    final photos = <String, String>{};
    final sp = await SharedPreferences.getInstance();

    Future<void> addPhoto(String path) async {
      final name = p.basename(path);
      if (photos.containsKey(name) || !_photoName.hasMatch(name)) return;
      final f = File(path);
      if (await f.exists()) photos[name] = base64Encode(await f.readAsBytes());
    }

    final folder = await PhotoStore.folder();
    for (final id in Shops.all) {
      final path = await AppDatabase.instance.pathFor(id);
      if (!File(path).existsSync()) continue; // a shop that was never opened
      files[id] = await File(path).readAsBytes();
      // the photos the bookings point to (a missing file is simply skipped)
      for (final path in await _photoPaths(id)) {
        await addPhoto(path);
      }
      // the shop's logo is kept by name in its details
      final logo = sp.getString(Shops.key('b', 'logo', shop: id)) ?? '';
      if (logo.isNotEmpty) await addPhoto(p.join(folder.path, logo));
    }
    final main = files[Shops.mainId];
    if (main == null) throw StateError('The shop has no data to back up');

    final prefs = <String, Object?>{
      for (final k in sp.getKeys())
        if (!_isDeviceOnly(k) && _allowedPrefKey.hasMatch(k)) k: sp.get(k),
    };

    return utf8.encode(
      jsonEncode({
        'format': _format,
        'version': 2,
        'created': DateTime.now().toIso8601String(),
        'prefs': prefs,
        'db': base64Encode(main),
        if (files.length > 1)
          'shopDbs': {
            for (final e in files.entries)
              if (e.key != Shops.mainId) e.key: base64Encode(e.value),
          },
        if (photos.isNotEmpty) 'photos': photos,
      }),
    );
  }

  static bool _looksLikeSqlite(Uint8List b) =>
      b.length >= _sqliteHeader.length &&
      List.generate(_sqliteHeader.length, (i) => b[i] == _sqliteHeader[i])
          .every((ok) => ok);

  /// The people of a shop file as stored, or none.
  static Future<List<Map<String, Object?>>> _staffIn(String path) async {
    if (!File(path).existsSync()) return const [];
    Database? db;
    try {
      db = await openDatabase(path, readOnly: true, singleInstance: false);
      return await db.query('staff_users');
    } catch (_) {
      return const []; // an older file has no staff table
    } finally {
      await db?.close();
    }
  }

  /// Opens a shop file on its own connection and runs [work] on it.
  static Future<void> _withFile(
    String path,
    Future<void> Function(Database db) work,
  ) async {
    final db = await openDatabase(path, singleInstance: false);
    try {
      await work(db);
    } finally {
      await db.close();
    }
  }

  /// Throws [FormatException] if [data] is not a valid backup. Replaces the
  /// current databases, photos and preferences on success. The people who can
  /// sign in on this phone are kept as they are.
  static Future<void> restore(Uint8List data) async {
    final Map<String, dynamic> json;
    final incoming = <String, Uint8List>{};
    try {
      json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      if (json['format'] != _format) throw const FormatException();
      incoming[Shops.mainId] = base64Decode(json['db'] as String);
      final extra = json['shopDbs'];
      if (extra is Map) {
        for (final e in extra.entries) {
          final id = e.key;
          final b64 = e.value;
          if (id is! String ||
              id == Shops.mainId ||
              !Shops.isValidId(id) ||
              b64 is! String) {
            continue; // not a shop we wrote: ignore it
          }
          incoming[id] = base64Decode(b64);
        }
      }
    } catch (_) {
      throw const FormatException('This is not a GellSoft RentPro backup file');
    }
    if (data.length > maxBackupBytes ||
        incoming.values.any((b) => b.length > maxBackupBytes)) {
      throw const FormatException('The backup file is too large');
    }
    for (final b in incoming.values) {
      if (!_looksLikeSqlite(b)) throw _invalidData;
      await _checkDatabase(b);
    }

    // Who may sign in is kept as it is on this phone, shop by shop.
    final people = <String, List<Map<String, Object?>>>{};
    for (final id in incoming.keys) {
      people[id] = await _staffIn(await AppDatabase.instance.pathFor(id));
    }

    // Write each new file beside the old one, then swap, so an interruption
    // can never leave a half-written database.
    await AppDatabase.instance.close();
    final written = <String, String>{};
    for (final e in incoming.entries) {
      final path = await AppDatabase.instance.pathFor(e.key);
      await File('$path.restoring').writeAsBytes(e.value, flush: true);
      written[e.key] = path;
    }
    // shops on this phone that the backup does not have are removed
    for (final id in Shops.all) {
      if (incoming.containsKey(id)) continue;
      final path = await AppDatabase.instance.pathFor(id);
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final f = File('$path$suffix');
        if (await f.exists()) await f.delete();
      }
    }
    for (final e in written.entries) {
      for (final suffix in ['-wal', '-shm', '-journal']) {
        final f = File('${e.value}$suffix');
        if (await f.exists()) await f.delete();
      }
      await File('${e.value}.restoring').rename(e.value);
    }
    for (final e in written.entries) {
      await _withFile(e.value, (db) async {
        await AppDatabase.ensureStaffTable(db);
        await db.transaction((txn) async {
          await txn.delete('staff_users');
          for (final row in people[e.key] ?? const []) {
            await txn.insert('staff_users', row);
          }
        });
      });
    }

    // Photos and logos: the old ones go, the backup's come in, and every photo
    // row is pointed at this phone's own folder (the folder differs between
    // phones).
    final folder = await PhotoStore.folder();
    for (final f in folder.listSync()) {
      if (f is File) {
        try {
          f.deleteSync();
        } catch (_) {
          // a file that cannot be removed is left; it is not referenced
        }
      }
    }
    final photos = json['photos'];
    if (photos is Map) {
      for (final e in photos.entries) {
        final name = e.key;
        final b64 = e.value;
        if (name is! String || b64 is! String || !_photoName.hasMatch(name)) {
          continue; // not a file we wrote: ignore it
        }
        try {
          await File(p.join(folder.path, name)).writeAsBytes(base64Decode(b64));
        } catch (_) {
          // a damaged photo should not fail the whole restore
        }
      }
    }
    for (final e in written.entries) {
      await _withFile(e.value, (db) async {
        for (final r in await db.query('booking_photos', columns: ['id', 'path'])) {
          final name = p.basename(r['path'] as String);
          await db.update(
            'booking_photos',
            {'path': p.join(folder.path, name)},
            where: 'id = ?',
            whereArgs: [r['id']],
          );
        }
      });
    }

    final sp = await SharedPreferences.getInstance();
    for (final k in sp.getKeys().toList()) {
      // Plan keys (e_...) stay too: restoring must not restart the trial.
      if (!_isDeviceOnly(k) && !k.startsWith('e_')) await sp.remove(k);
    }
    final prefs = (json['prefs'] as Map?) ?? {};
    for (final e in prefs.entries) {
      final k = e.key;
      final v = e.value;
      if (k is! String || _isDeviceOnly(k)) continue;
      if (!_allowedPrefKey.hasMatch(k)) continue; // not one of ours: ignore
      if (v is String) {
        if (v.length <= 20000) await sp.setString(k, v);
      } else if (v is bool) {
        await sp.setBool(k, v);
      } else if (v is int) {
        await sp.setInt(k, v);
      } else if (v is double) {
        await sp.setDouble(k, v);
      } else if (v is List && v.length <= 100) {
        await sp.setStringList(k, v.map((x) => '$x').toList());
      }
    }
    // a backup made before there were several shops has one: the first
    await Shops.load();
    // the open shop must still be one that exists
    if (!incoming.containsKey(Shops.activeId)) {
      await sp.setString('s_activeshop', Shops.mainId);
      Shops.activeId = Shops.mainId;
    }
  }
}
