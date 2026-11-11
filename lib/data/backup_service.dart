import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'database.dart';
import 'photo_store.dart';

/// A backup is one JSON file: the SQLite database (base64), the booking photos
/// (base64, by file name) and the preferences (shop details, GST and reminder
/// settings).
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
  };

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

  /// Everything in one file: the database, the photos it points to, and the
  /// settings.
  static Future<Uint8List> create() async {
    final db = await AppDatabase.instance.db;
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // Not in WAL mode; nothing to flush.
    }
    final bytes = await File(await AppDatabase.instance.filePath).readAsBytes();

    // the photos the bookings point to (a missing file is simply skipped)
    final photos = <String, String>{};
    for (final r in await db.query('booking_photos', columns: ['path'])) {
      final path = r['path'] as String;
      final name = p.basename(path);
      if (photos.containsKey(name) || !_photoName.hasMatch(name)) continue;
      final f = File(path);
      if (await f.exists()) photos[name] = base64Encode(await f.readAsBytes());
    }

    final sp = await SharedPreferences.getInstance();
    final prefs = <String, Object?>{
      for (final k in sp.getKeys())
        if (!_deviceOnly.contains(k) && _allowedPrefKey.hasMatch(k))
          k: sp.get(k),
    };

    return utf8.encode(
      jsonEncode({
        'format': _format,
        'version': 1,
        'created': DateTime.now().toIso8601String(),
        'prefs': prefs,
        'db': base64Encode(bytes),
        if (photos.isNotEmpty) 'photos': photos,
      }),
    );
  }

  /// Throws [FormatException] if [data] is not a valid backup. Replaces the
  /// current database, photos and preferences on success.
  static Future<void> restore(Uint8List data) async {
    final Map<String, dynamic> json;
    final Uint8List dbBytes;
    try {
      json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      if (json['format'] != _format) throw const FormatException();
      dbBytes = base64Decode(json['db'] as String);
    } catch (_) {
      throw const FormatException('This is not a GellSoft RentPro backup file');
    }
    if (data.length > maxBackupBytes || dbBytes.length > maxBackupBytes) {
      throw const FormatException('The backup file is too large');
    }
    if (dbBytes.length < _sqliteHeader.length ||
        !List.generate(
          _sqliteHeader.length,
          (i) => dbBytes[i] == _sqliteHeader[i],
        ).every((ok) => ok)) {
      throw _invalidData;
    }
    await _checkDatabase(dbBytes);

    // Write the new file beside the old one, then swap, so an interruption
    // can never leave a half-written database.
    final path = await AppDatabase.instance.filePath;
    final incoming = File('$path.restoring');
    await incoming.writeAsBytes(dbBytes, flush: true);
    await AppDatabase.instance.close();
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final f = File('$path$suffix');
      if (await f.exists()) await f.delete();
    }
    await incoming.rename(path);

    // Photos: the old ones go, the backup's come in, and every photo row is
    // pointed at this phone's own folder (the folder differs between phones).
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
    final d = await AppDatabase.instance.db;
    for (final r in await d.query('booking_photos', columns: ['id', 'path'])) {
      final name = p.basename(r['path'] as String);
      await d.update(
        'booking_photos',
        {'path': p.join(folder.path, name)},
        where: 'id = ?',
        whereArgs: [r['id']],
      );
    }

    final sp = await SharedPreferences.getInstance();
    for (final k in sp.getKeys().toList()) {
      // Plan keys (e_...) stay too: restoring must not restart the trial.
      if (!_deviceOnly.contains(k) && !k.startsWith('e_')) await sp.remove(k);
    }
    final prefs = (json['prefs'] as Map?) ?? {};
    for (final e in prefs.entries) {
      final k = e.key;
      final v = e.value;
      if (k is! String || _deviceOnly.contains(k)) continue;
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
  }
}
