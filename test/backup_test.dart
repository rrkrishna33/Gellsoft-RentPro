import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/booking_math.dart';
import 'package:gellsoft_rentpro/data/backup_service.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/business_profile.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/photo_store.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;
  final bookings = BookingRepo();
  late int booking;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'b_name': 'Royal Costumes',
      'b_type': 'costume',
      'b_gst': true,
      'n_hour': 7,
      'e_install_id': 'keep-me',
      'acct_email': 'someone@example.com',
      'last_backup': '2027-01-01',
      's_hideamounts': true,
      'other_app_key': 'ignored',
    });
    dir = await Directory.systemTemp.createTemp('rentpro_backup');
    AppDatabase.pathOverride = p.join(dir.path, 't.db');
    PhotoStore.folderOverride = Directory(p.join(dir.path, 'photos'))
      ..createSync();
    final anu = await CustomerRepo().save(
      Customer(name: 'Anu', phone: '9000000001', createdAt: DateTime(2027)),
    );
    final gown = await ItemRepo().save(
      RentItem(name: 'Red gown', rate: 1000, gstRate: 18, createdAt: DateTime(2027)),
    );
    booking = await bookings.create(
      BookingDraft(
        customerId: anu,
        eventDate: DateTime(2027, 3, 10),
        pickupDate: DateTime(2027, 3, 9),
        returnDate: DateTime(2027, 3, 11),
        itemIds: [gown],
      ),
      isPro: true,
      advance: 300,
      gst: const GstConfig(enabled: true),
      now: DateTime(2027, 3, 1),
    );
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AppDatabase.pathOverride = null;
    PhotoStore.folderOverride = null;
    await dir.delete(recursive: true);
  });

  Future<String> addPhoto(String name, List<int> bytes) async {
    final path = p.join(PhotoStore.folderOverride!.path, name);
    File(path).writeAsBytesSync(bytes);
    await bookings.addPhoto(booking, path: path, stage: 'pickup', isPro: true);
    return path;
  }

  test('a backup carries the data, the photos and the settings', () async {
    await addPhoto('aaaaaaaa-1111.jpg', [1, 2, 3, 4]);
    final bytes = await BackupService.create();
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(json['format'], 'gellsoft_rentpro_backup');
    expect((json['photos'] as Map).keys, ['aaaaaaaa-1111.jpg']);
    final prefs = json['prefs'] as Map;
    expect(prefs['b_name'], 'Royal Costumes');
    expect(prefs['n_hour'], 7);
    expect(prefs.containsKey('e_install_id'), isFalse, reason: 'the plan stays on the phone');
    expect(prefs.containsKey('acct_email'), isFalse);
    expect(prefs.containsKey('last_backup'), isFalse);
    expect(prefs.containsKey('s_hideamounts'), isFalse);
    expect(prefs.containsKey('other_app_key'), isFalse);
  });

  test('restore brings everything back on a phone with a different photo folder', () async {
    final photo = await addPhoto('bbbbbbbb-2222.jpg', [9, 8, 7]);
    final bytes = await BackupService.create();

    // change everything, as a new phone would have it
    await bookings.cancel(booking);
    File(photo).deleteSync();
    final sp = await SharedPreferences.getInstance();
    await sp.setString('b_name', 'Someone else');
    await sp.setString('b_leftover', 'x');
    PhotoStore.folderOverride = Directory(p.join(dir.path, 'photos_new'))
      ..createSync();

    await BackupService.restore(bytes);

    final b = (await bookings.get(booking))!;
    expect(b.status.name, 'booked', reason: 'the cancel was undone by the restore');
    expect(b.customerName, 'Anu');
    expect(b.rentPaid, 300);
    expect(b.photos.length, 1);
    final restored = b.photos.single.path;
    expect(p.dirname(restored), PhotoStore.folderOverride!.path,
        reason: 'the photo row points at this phone\'s folder');
    expect(File(restored).readAsBytesSync(), [9, 8, 7]);

    final after = await SharedPreferences.getInstance();
    expect(after.getString('b_name'), 'Royal Costumes');
    expect(after.containsKey('b_leftover'), isFalse);
    expect(after.getString('e_install_id'), 'keep-me', reason: 'restoring must not restart the trial');
    expect(after.getString('acct_email'), 'someone@example.com');
    expect(after.getBool('s_hideamounts'), isTrue, reason: 'a choice of this phone');
    expect((await BusinessProfile.load())!.gstEnabled, isTrue);
  });

  test('old photos that are not in the backup are removed', () async {
    final bytes = await BackupService.create(); // no photos yet
    final stray = await addPhoto('cccccccc-3333.jpg', [1]);
    await BackupService.restore(bytes);
    expect(File(stray).existsSync(), isFalse);
    expect((await bookings.get(booking))!.photos, isEmpty);
  });

  test('a backup of a shop with no photos works', () async {
    final bytes = await BackupService.create();
    expect((jsonDecode(utf8.decode(bytes)) as Map).containsKey('photos'), isFalse);
    await BackupService.restore(bytes);
    expect((await bookings.get(booking))!.customerName, 'Anu');
  });

  group('bad files are refused and change nothing', () {
    Future<void> refused(List<int> data, [String? why]) async {
      try {
        await BackupService.restore(Uint8List.fromList(data));
        fail('should have been refused');
      } on FormatException catch (e) {
        if (why != null) expect(e.message, contains(why));
      }
      expect((await bookings.get(booking))!.customerName, 'Anu');
    }

    test('not JSON', () => refused(utf8.encode('hello'), 'not a GellSoft RentPro backup'));

    test('another app\'s backup', () => refused(
      utf8.encode(jsonEncode({'format': 'gellsoft_billpro_backup', 'db': 'AAAA'})),
      'not a GellSoft RentPro backup',
    ));

    test('not a database', () => refused(
      utf8.encode(jsonEncode({
        'format': 'gellsoft_rentpro_backup',
        'db': base64Encode(utf8.encode('this is not sqlite at all, only text')),
      })),
    ));

    test('a database without this app\'s tables', () async {
      final other = p.join(dir.path, 'other.db');
      final odb = await databaseFactory.openDatabase(
        other,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, v) => d.execute('CREATE TABLE junk(id INTEGER)'),
        ),
      );
      await odb.close();
      await refused(
        utf8.encode(jsonEncode({
          'format': 'gellsoft_rentpro_backup',
          'db': base64Encode(File(other).readAsBytesSync()),
        })),
        'valid data',
      );
    });

    test('a database with a hidden trigger', () async {
      final live = await AppDatabase.instance.db;
      await live.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      final copy = p.join(dir.path, 'trigger.db');
      File(await AppDatabase.instance.filePath).copySync(copy);
      final tdb = await databaseFactory.openDatabase(copy);
      await tdb.execute(
        'CREATE TRIGGER evil AFTER INSERT ON items BEGIN DELETE FROM customers; END',
      );
      await tdb.close();
      await refused(
        utf8.encode(jsonEncode({
          'format': 'gellsoft_rentpro_backup',
          'db': base64Encode(File(copy).readAsBytesSync()),
        })),
        'valid data',
      );
    });
  });

  test('odd photo names and preference names in a backup are ignored', () async {
    final good = jsonDecode(utf8.decode(await BackupService.create())) as Map<String, dynamic>;
    good['photos'] = {
      '../../escape.jpg': base64Encode([1]),
      'dddddddd-4444.jpg': base64Encode([5, 5]),
    };
    good['prefs'] = {
      ...(good['prefs'] as Map),
      'x_evil': 'no',
      'e_install_id': 'hijack',
      'b_ok': 'yes',
    };
    await BackupService.restore(Uint8List.fromList(utf8.encode(jsonEncode(good))));
    final folder = PhotoStore.folderOverride!;
    expect(File(p.join(folder.path, 'dddddddd-4444.jpg')).existsSync(), isTrue);
    expect(File(p.join(dir.path, 'escape.jpg')).existsSync(), isFalse);
    expect(File(p.join(folder.parent.parent.path, 'escape.jpg')).existsSync(), isFalse);
    final sp = await SharedPreferences.getInstance();
    expect(sp.containsKey('x_evil'), isFalse);
    expect(sp.getString('e_install_id'), 'keep-me');
    expect(sp.getString('b_ok'), 'yes');
  });

  test('the suggested file name carries the date', () {
    expect(BackupService.suggestedName(), matches(RegExp(r'^gellsoft_rentpro_backup_\d{8}_\d{4}\.json$')));
  });
}
