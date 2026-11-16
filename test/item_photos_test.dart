import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/data/backup_service.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/photo_store.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:gellsoft_rentpro/subscription/plan.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;
  final items = ItemRepo();
  late int gown, tent;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'b_name': 'Shop', 'b_type': 'costume'});
    dir = await Directory.systemTemp.createTemp('rentpro_item_photos');
    AppDatabase.pathOverride = p.join(dir.path, 't.db');
    PhotoStore.folderOverride = Directory(p.join(dir.path, 'photos'))
      ..createSync();
    gown = await items.save(
      RentItem(name: 'Gown', rate: 1000, createdAt: DateTime(2027)),
    );
    tent = await items.save(
      RentItem(name: 'Tent', rate: 500, createdAt: DateTime(2027)),
    );
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AppDatabase.pathOverride = null;
    PhotoStore.folderOverride = null;
    await dir.delete(recursive: true);
  });

  String file(String name, [List<int> bytes = const [1, 2, 3]]) {
    final path = p.join(PhotoStore.folderOverride!.path, name);
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  Future<void> expectLimit(Future<Object?> f) async {
    try {
      await f;
      fail('expected the limit');
    } on BookingException catch (e) {
      expect(e.error, BookingError.limitReached);
    }
  }

  group('pictures of an item', () {
    test('an item has none until one is added', () async {
      expect(await items.photosOf(gown), isEmpty);
      expect(await items.covers(), isEmpty);
    });

    test('the free plan keeps one picture, Pro keeps five', () async {
      await items.addPhoto(gown, file('aaaaaaaa-0001.jpg'), isPro: false);
      await expectLimit(
        items.addPhoto(gown, file('aaaaaaaa-0002.jpg'), isPro: false),
      );
      for (var i = 2; i <= 5; i++) {
        await items.addPhoto(gown, file('aaaaaaaa-000$i.jpg'), isPro: true);
      }
      expect((await items.photosOf(gown)).length, proPhotosPerItem);
      await expectLimit(
        items.addPhoto(gown, file('aaaaaaaa-0006.jpg'), isPro: true),
      );
      // another item has its own count
      await items.addPhoto(tent, file('bbbbbbbb-0001.jpg'), isPro: false);
    });

    test('pictures keep the order they were added in', () async {
      await items.addPhoto(gown, file('aaaaaaaa-0001.jpg'), isPro: true);
      await items.addPhoto(gown, file('aaaaaaaa-0002.jpg'), isPro: true);
      await items.addPhoto(gown, file('aaaaaaaa-0003.jpg'), isPro: true);
      final names = (await items.photosOf(gown)).map((x) => p.basename(x.path));
      expect(names, ['aaaaaaaa-0001.jpg', 'aaaaaaaa-0002.jpg', 'aaaaaaaa-0003.jpg']);
    });

    test('the cover is the first picture, and can be changed', () async {
      final a = await items.addPhoto(gown, file('aaaaaaaa-0001.jpg'), isPro: true);
      final b = await items.addPhoto(gown, file('aaaaaaaa-0002.jpg'), isPro: true);
      final c = await items.addPhoto(gown, file('aaaaaaaa-0003.jpg'), isPro: true);
      expect(p.basename((await items.covers())[gown]!), 'aaaaaaaa-0001.jpg');
      await items.setPhotoOrder(gown, [c, a]);
      final order = (await items.photosOf(gown)).map((x) => x.id).toList();
      expect(order, [c, a, b], reason: 'the ones not listed follow');
      expect(p.basename((await items.covers())[gown]!), 'aaaaaaaa-0003.jpg');
    });

    test('removing a picture gives back its file path, and the next becomes the cover', () async {
      final a = await items.addPhoto(gown, file('aaaaaaaa-0001.jpg'), isPro: true);
      await items.addPhoto(gown, file('aaaaaaaa-0002.jpg'), isPro: true);
      final path = await items.removePhoto(a);
      expect(p.basename(path!), 'aaaaaaaa-0001.jpg');
      expect(p.basename((await items.covers())[gown]!), 'aaaaaaaa-0002.jpg');
      expect(await items.removePhoto(a), isNull, reason: 'already gone');
    });

    test('covers has one entry per item', () async {
      await items.addPhoto(gown, file('aaaaaaaa-0001.jpg'), isPro: true);
      await items.addPhoto(gown, file('aaaaaaaa-0002.jpg'), isPro: true);
      await items.addPhoto(tent, file('bbbbbbbb-0001.jpg'), isPro: true);
      final covers = await items.covers();
      expect(covers.keys.toSet(), {gown, tent});
    });

    test('after Pro ends, the pictures stay but no more can be added', () async {
      for (var i = 1; i <= 3; i++) {
        await items.addPhoto(gown, file('aaaaaaaa-000$i.jpg'), isPro: true);
      }
      await expectLimit(
        items.addPhoto(gown, file('aaaaaaaa-0009.jpg'), isPro: false),
      );
      expect((await items.photosOf(gown)).length, 3);
    });
  });

  group('backup', () {
    test('item pictures go into a backup and come back on another phone', () async {
      final path = file('cccccccc-0001.jpg', [9, 8, 7]);
      await items.addPhoto(gown, path, isPro: true);
      final bytes = await BackupService.create();

      File(path).deleteSync();
      await items.removePhoto((await items.photosOf(gown)).single.id);
      PhotoStore.folderOverride = Directory(p.join(dir.path, 'photos_new'))
        ..createSync();

      await BackupService.restore(bytes);

      final back = await items.photosOf(gown);
      expect(back.length, 1);
      expect(p.dirname(back.single.path), PhotoStore.folderOverride!.path,
          reason: 'the row points at this phone\'s folder');
      expect(File(back.single.path).readAsBytesSync(), [9, 8, 7]);
    });
  });
}
