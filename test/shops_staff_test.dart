import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/constants.dart';
import 'package:gellsoft_rentpro/data/app_settings.dart';
import 'package:gellsoft_rentpro/data/backup_service.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/business_profile.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/photo_store.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:gellsoft_rentpro/data/shops.dart';
import 'package:gellsoft_rentpro/data/staff.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'b_name': 'Royal Costumes',
      'b_type': 'costume',
      'e_install_id': 'keep-me',
    });
    Shops.resetForTests();
    forgetSignedInPerson();
    dir = await Directory.systemTemp.createTemp('rentpro_shops');
    AppDatabase.pathOverride = p.join(dir.path, 'main.db');
    PhotoStore.folderOverride = Directory(p.join(dir.path, 'photos'))
      ..createSync();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AppDatabase.pathOverride = null;
    PhotoStore.folderOverride = null;
    Shops.resetForTests();
    await dir.delete(recursive: true);
  });

  group('shops', () {
    test('the first shop keeps the old names; others are marked with their id', () {
      expect(Shops.key('b', 'name'), 'b_name');
      expect(Shops.key('b', 'name', shop: 's2'), 'b_s2_name');
      expect(Shops.key('s', 'recovhash', shop: 's3'), 's_s3_recovhash');
      expect(Shops.dbName(Shops.mainId), 'gellsoft_rentpro.db');
      expect(Shops.dbName('s2'), 'gellsoft_rentpro_s2.db');
    });

    test('adding shops gives s2, s3 and is remembered', () async {
      expect(await Shops.create(), 's2');
      expect(await Shops.create(), 's3');
      expect(Shops.all, ['main', 's2', 's3']);
      await Shops.activate('s3');
      Shops.resetForTests();
      expect(Shops.activeId, 'main');
      await Shops.load();
      expect(Shops.all, ['main', 's2', 's3']);
      expect(Shops.activeId, 's3', reason: 'the open shop is remembered');
    });

    test('a damaged list or an unknown open shop falls back to the first', () async {
      SharedPreferences.setMockInitialValues({
        's_shopids': ['s2', '../evil', 'x9', 's7'],
        's_activeshop': 's9',
      });
      await Shops.load();
      expect(Shops.all, ['main', 's2', 's7'], reason: 'only ids we wrote');
      expect(Shops.activeId, 'main');
    });

    test('each shop has its own items, customers and bookings', () async {
      final items = ItemRepo();
      await items.save(RentItem(name: 'Main gown', rate: 100, createdAt: DateTime(2027)));
      final second = await Shops.create();
      await Shops.activate(second);
      expect(await items.list(), isEmpty, reason: 'the new shop starts empty');
      await items.save(RentItem(name: 'Branch chair', rate: 20, createdAt: DateTime(2027)));
      expect((await items.list()).single.name, 'Branch chair');
      await Shops.activate(Shops.mainId);
      expect((await items.list()).single.name, 'Main gown');
      expect(File(await AppDatabase.instance.pathFor('s2')).existsSync(), isTrue);
    });

    test('each shop has its own details, GST settings and logo', () async {
      await const BusinessProfile(
        name: 'Royal Costumes',
        type: ShopType.costume,
        gstEnabled: true,
        invoicePrefix: 'ROY',
        logoName: 'aaaaaaaa-0001.png',
      ).save();
      final id = await Shops.create();
      await const BusinessProfile(
        name: 'Glow Studio',
        type: ShopType.makeup,
        invoicePrefix: 'GLW',
      ).save(shop: id);

      final main = (await BusinessProfile.load())!;
      expect(main.name, 'Royal Costumes');
      expect(main.gstEnabled, isTrue);
      expect(main.logoName, 'aaaaaaaa-0001.png');
      final glow = (await BusinessProfile.load(shop: id))!;
      expect(glow.name, 'Glow Studio');
      expect(glow.type.isService, isTrue);
      expect(glow.gstEnabled, isFalse, reason: 'GST is a setting of each shop');
      expect(glow.logoName, '');
      expect(glow.invoicePrefix, 'GLW');

      // opening the second shop reads the second shop's details
      await Shops.activate(id);
      expect((await BusinessProfile.load())!.name, 'Glow Studio');
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('b_s2_name'), 'Glow Studio');
      expect(sp.getString('b_name'), 'Royal Costumes');
    });

    test('a logo is found by name in the photo folder, and missing is fine', () async {
      final folder = PhotoStore.folderOverride!;
      File(p.join(folder.path, 'bbbbbbbb-0002.png')).writeAsBytesSync([1, 2, 3]);
      const withLogo = BusinessProfile(
        name: 'A',
        type: ShopType.other,
        logoName: 'bbbbbbbb-0002.png',
      );
      expect((await withLogo.logoFile())!.existsSync(), isTrue);
      expect(await withLogo.logoBytes(), [1, 2, 3]);
      const gone = BusinessProfile(name: 'A', type: ShopType.other, logoName: 'cccccccc-0003.png');
      expect(await gone.logoFile(), isNull);
      expect(await gone.logoBytes(), isNull);
      expect(await const BusinessProfile(name: 'A', type: ShopType.other).logoFile(), isNull);
    });

    test('deleting a shop removes its data and settings; the first cannot go', () async {
      final id = await Shops.create();
      await const BusinessProfile(name: 'Branch', type: ShopType.other).save(shop: id);
      await Shops.activate(id);
      await ItemRepo().save(RentItem(name: 'X', rate: 1, createdAt: DateTime(2027)));
      final file = File(await AppDatabase.instance.pathFor(id));
      expect(file.existsSync(), isTrue);

      await Shops.remove(Shops.mainId);
      expect(Shops.all, ['main', id], reason: 'the first shop is never deleted');

      await Shops.remove(id); // it was open: the first opens instead
      expect(Shops.all, ['main']);
      expect(Shops.activeId, 'main');
      expect(file.existsSync(), isFalse);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getKeys().where((k) => k.contains('_s2_')), isEmpty);
      expect(sp.getString('b_name'), 'Royal Costumes');
    });

    test('a shop id must be one we make', () {
      expect(Shops.isValidId('main'), isTrue);
      expect(Shops.isValidId('s2'), isTrue);
      expect(Shops.isValidId('s999'), isTrue);
      expect(Shops.isValidId('s1000'), isFalse);
      expect(Shops.isValidId('../x'), isFalse);
      expect(Shops.isValidId('S2'), isFalse);
    });
  });

  group('staff logins', () {
    final repo = StaffRepo();

    test('the first person is an Admin; names are unique and a PIN has 4 to 6 digits', () async {
      final admin = await repo.add(name: 'Krishna', role: Role.admin, pin: '1234');
      expect(admin.checkPin('1234'), isTrue);
      expect(admin.checkPin('1235'), isFalse);
      expect(admin.pinHash, startsWith('v2:'), reason: 'salted PBKDF2, never the PIN');
      expect(admin.pinHash, isNot(contains('1234')));

      await expectLater(
        repo.add(name: ' krishna ', role: Role.staff, pin: '5555'),
        throwsA(isA<StaffException>().having((e) => e.error, 'error', StaffError.nameTaken)),
      );
      await expectLater(
        repo.add(name: '  ', role: Role.staff, pin: '5555'),
        throwsA(isA<StaffException>().having((e) => e.error, 'error', StaffError.nameEmpty)),
      );
      for (final bad in ['123', '1234567', 'abcd', '12 34']) {
        await expectLater(
          repo.add(name: 'Meena', role: Role.cashier, pin: bad),
          throwsA(isA<StaffException>().having((e) => e.error, 'error', StaffError.badPin)),
        );
      }
    });

    test('everyone is listed, Admins first, then by name', () async {
      await repo.add(name: 'Zed', role: Role.cashier, pin: '1111');
      await repo.add(name: 'Anu', role: Role.cashier, pin: '2222');
      await repo.add(name: 'Mani', role: Role.staff, pin: '3333');
      await repo.add(name: 'Krishna', role: Role.admin, pin: '4444');
      expect((await repo.list()).map((u) => u.name), ['Krishna', 'Mani', 'Anu', 'Zed']);
    });

    test('there is always an active Admin who can get back in', () async {
      final a = await repo.add(name: 'Krishna', role: Role.admin, pin: '1234');
      Matcher lastAdmin() => throwsA(
        isA<StaffException>().having((e) => e.error, 'error', StaffError.lastAdmin),
      );
      await expectLater(repo.update(a.uuid, role: Role.staff), lastAdmin());
      await expectLater(repo.update(a.uuid, active: false), lastAdmin());
      await expectLater(repo.remove(a.uuid), lastAdmin());
      // with a second Admin the first can step down
      final b = await repo.add(name: 'Second', role: Role.admin, pin: '5678');
      await repo.update(a.uuid, role: Role.staff);
      expect((await repo.list()).first.uuid, b.uuid);
      await expectLater(repo.remove(b.uuid), lastAdmin());
    });

    test('a person can be renamed, switched off, given a new PIN and removed', () async {
      await repo.add(name: 'Krishna', role: Role.admin, pin: '1234');
      final m = await repo.add(name: 'Meena', role: Role.cashier, pin: '1111');
      await repo.update(m.uuid, name: 'Meena K', role: Role.staff, active: false);
      var got = (await repo.list()).firstWhere((u) => u.uuid == m.uuid);
      expect(got.name, 'Meena K');
      expect(got.role, Role.staff);
      expect(got.active, isFalse);
      await repo.setPin(m.uuid, '987654');
      got = (await repo.list()).firstWhere((u) => u.uuid == m.uuid);
      expect(got.checkPin('987654'), isTrue);
      expect(got.checkPin('1111'), isFalse);
      await expectLater(repo.setPin(m.uuid, '12'), throwsA(isA<StaffException>()));
      await repo.remove(m.uuid);
      expect((await repo.list()).map((u) => u.name), ['Krishna']);
      await repo.clearAll();
      expect(await repo.list(), isEmpty);
    });

    test('what each role may do', () {
      for (final p in Permission.values) {
        expect(Role.admin.can(p), isTrue, reason: 'the owner may do everything: $p');
      }
      // staff run the day, but cannot cancel, export, change settings or manage people
      for (final p in [
        Permission.book,
        Permission.collectPayments,
        Permission.giveDiscount,
        Permission.editItems,
        Permission.editCustomers,
        Permission.seeReports,
      ]) {
        expect(Role.staff.can(p), isTrue, reason: '$p');
      }
      for (final p in [
        Permission.cancelBookings,
        Permission.exportData,
        Permission.settings,
        Permission.manageStaff,
      ]) {
        expect(Role.staff.can(p), isFalse, reason: '$p');
      }
      // the counter: bookings and payments only
      expect(Role.cashier.can(Permission.book), isTrue);
      expect(Role.cashier.can(Permission.collectPayments), isTrue);
      for (final p in Permission.values) {
        if (p == Permission.book || p == Permission.collectPayments) continue;
        expect(Role.cashier.can(p), isFalse, reason: '$p');
      }
      // an unknown stored role gets the least, never the most
      expect(Role.fromCode('owner'), Role.cashier);
      expect(Role.fromCode(null), Role.cashier);
      expect(Role.fromCode('admin'), Role.admin);
    });

    test('with logins off nobody is signed in and everything is allowed', () {
      const open = Perms(null);
      for (final p in Permission.values) {
        expect(open.can(p), isTrue);
      }
      expect(open.name, '');
    });

    test('the recovery code works once per shop and only for that shop', () async {
      final code = await RecoveryCode.issue();
      expect(RegExp(r'^\d{4} \d{4}$').hasMatch(code), isTrue);
      expect(await RecoveryCode.check(code), isTrue);
      expect(await RecoveryCode.check(code.replaceAll(' ', '')), isTrue);
      expect(await RecoveryCode.check('0000 0000'), isFalse);
      expect(await RecoveryCode.check('1234'), isFalse);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('s_recovhash'), isNot(contains(code.replaceAll(' ', ''))));

      // the second shop has its own people and its own code
      final id = await Shops.create();
      await Shops.activate(id);
      expect(await RecoveryCode.check(code), isFalse);
      final other = await RecoveryCode.issue();
      expect(await RecoveryCode.check(other), isTrue);
      expect(sp.getString('s_s2_recovhash'), isNotNull);
      await RecoveryCode.clear();
      expect(await RecoveryCode.check(other), isFalse);
      await Shops.activate(Shops.mainId);
      expect(await RecoveryCode.check(code), isTrue);
    });

    test('each shop has its own people', () async {
      await repo.add(name: 'Krishna', role: Role.admin, pin: '1234');
      final id = await Shops.create();
      await Shops.activate(id);
      expect(await repo.list(), isEmpty, reason: 'the branch has no logins yet');
      await repo.add(name: 'Branch boss', role: Role.admin, pin: '9999');
      await Shops.activate(Shops.mainId);
      expect((await repo.list()).map((u) => u.name), ['Krishna']);
    });

    test('PIN hashes verify and refuse damaged values', () {
      final salt = AppSettings.newSalt();
      final h = AppSettings.hashPin('2468', salt);
      expect(AppSettings.verifyPin('2468', h, salt), isTrue);
      expect(AppSettings.verifyPin('2469', h, salt), isFalse);
      expect(AppSettings.verifyPin('2468', '', salt), isFalse);
      expect(AppSettings.verifyPin('2468', 'v2:99999999:abc', salt), isFalse,
          reason: 'a huge round count must not make the check run for ages');
      expect(AppSettings.verifyPin('2468', 'plain', salt), isFalse);
      expect(AppSettings.newSalt(), isNot(AppSettings.newSalt()));
    });
  });

  group('backup with several shops', () {
    final bookings = BookingRepo();

    /// Fills the open shop with a customer, an item and a booking with a photo.
    Future<int> fill(String who, String photo) async {
      final c = await CustomerRepo().save(
        Customer(name: who, phone: '9000000001', createdAt: DateTime(2027)),
      );
      final i = await ItemRepo().save(
        RentItem(name: '$who item', rate: 100, quantity: 5, createdAt: DateTime(2027)),
      );
      final b = await bookings.create(
        BookingDraft(
          customerId: c,
          eventDate: DateTime(2027, 3, 10),
          pickupDate: DateTime(2027, 3, 9),
          returnDate: DateTime(2027, 3, 11),
          itemIds: [i],
          quantities: {i: 3},
        ),
        isPro: true,
        now: DateTime(2027, 3, 1),
      );
      final path = p.join(PhotoStore.folderOverride!.path, photo);
      File(path).writeAsBytesSync(utf8.encode(who));
      await bookings.addPhoto(b, path: path, stage: 'pickup', isPro: true);
      return b;
    }

    Future<void> twoShops() async {
      // the logo is kept by name, in the same folder as the photos
      final logo = p.join(PhotoStore.folderOverride!.path, 'aaaaaaaa-1111.png');
      File(logo).writeAsBytesSync([7, 7, 7]);
      await const BusinessProfile(
        name: 'Royal Costumes',
        type: ShopType.costume,
        logoName: 'aaaaaaaa-1111.png',
      ).save();
      await fill('Anu', 'bbbbbbbb-2222.jpg');
      final id = await Shops.create();
      await const BusinessProfile(name: 'Glow Studio', type: ShopType.makeup).save(shop: id);
      await Shops.activate(id);
      await fill('Bala', 'cccccccc-3333.jpg');
      await Shops.activate(Shops.mainId);
    }

    test('every shop, its photos and its logo are in one backup', () async {
      await twoShops();
      final json =
          jsonDecode(utf8.decode(await BackupService.create())) as Map<String, dynamic>;
      expect(json['version'], 2);
      expect((json['shopDbs'] as Map).keys, ['s2']);
      expect((json['photos'] as Map).keys.toSet(), {
        'aaaaaaaa-1111.png',
        'bbbbbbbb-2222.jpg',
        'cccccccc-3333.jpg',
      });
      final prefs = json['prefs'] as Map;
      expect(prefs['b_name'], 'Royal Costumes');
      expect(prefs['b_s2_name'], 'Glow Studio');
      expect(prefs['s_shopids'], ['s2']);
      expect(prefs.containsKey('s_activeshop'), isFalse, reason: 'a choice of this phone');
      expect(prefs.containsKey('e_install_id'), isFalse);
    });

    test('restore brings every shop back, with photos and logo on a new phone', () async {
      await twoShops();
      final bytes = await BackupService.create();

      // a new phone: nothing of the old data, another photo folder
      await AppDatabase.instance.close();
      for (final f in dir.listSync().whereType<File>()) {
        f.deleteSync();
      }
      SharedPreferences.setMockInitialValues({'e_install_id': 'keep-me'});
      Shops.resetForTests();
      PhotoStore.folderOverride = Directory(p.join(dir.path, 'photos_new'))
        ..createSync();

      await BackupService.restore(bytes);
      expect(Shops.all, ['main', 's2']);
      expect(Shops.activeId, 'main');

      // the first shop
      expect((await BusinessProfile.load())!.name, 'Royal Costumes');
      final mainBooking = (await bookings.list(filter: BookingFilter.upcoming)).single;
      expect(mainBooking.customerName, 'Anu');
      expect(mainBooking.lines.single.qty, 3);
      final mainPhoto = mainBooking.photos.single.path;
      expect(p.dirname(mainPhoto), PhotoStore.folderOverride!.path);
      expect(File(mainPhoto).readAsStringSync(), 'Anu');
      final logo = await (await BusinessProfile.load())!.logoFile();
      expect(logo!.readAsBytesSync(), [7, 7, 7], reason: 'the logo came back');

      // the second shop
      await Shops.activate('s2');
      expect((await BusinessProfile.load())!.type.isService, isTrue);
      final second = (await bookings.list(filter: BookingFilter.upcoming)).single;
      expect(second.customerName, 'Bala');
      expect(File(second.photos.single.path).readAsStringSync(), 'Bala');
      expect(p.dirname(second.photos.single.path), PhotoStore.folderOverride!.path);

      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('e_install_id'), 'keep-me');
    });

    test('a shop on the phone that the backup does not have is removed', () async {
      final bytes = await BackupService.create(); // only the first shop
      final id = await Shops.create();
      await const BusinessProfile(name: 'Branch', type: ShopType.other).save(shop: id);
      await Shops.activate(id);
      await ItemRepo().save(RentItem(name: 'Y', rate: 1, createdAt: DateTime(2027)));
      final file = File(await AppDatabase.instance.pathFor(id));
      expect(file.existsSync(), isTrue);

      await BackupService.restore(bytes);
      expect(Shops.all, ['main']);
      expect(Shops.activeId, 'main', reason: 'the open shop no longer exists');
      expect(file.existsSync(), isFalse);
      final sp = await SharedPreferences.getInstance();
      expect(sp.containsKey('b_s2_name'), isFalse);
    });

    test('a backup made before there were several shops restores the one shop', () async {
      // the old format: one database, version 1
      final live = await AppDatabase.instance.db;
      await live.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      final old = utf8.encode(jsonEncode({
        'format': 'gellsoft_rentpro_backup',
        'version': 1,
        'created': '2027-01-01T00:00:00',
        'prefs': {'b_name': 'Old shop', 'b_type': 'costume'},
        'db': base64Encode(File(await AppDatabase.instance.filePath).readAsBytesSync()),
      }));
      final id = await Shops.create();
      await Shops.activate(id);
      await BackupService.restore(Uint8List.fromList(old));
      expect(Shops.all, ['main']);
      expect(Shops.activeId, 'main');
      expect((await BusinessProfile.load())!.name, 'Old shop');
    });

    test('a shop id that is not ours inside a backup is ignored', () async {
      final bytes = await BackupService.create();
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      json['shopDbs'] = {'../escape': json['db'], 'zzz': json['db']};
      await BackupService.restore(Uint8List.fromList(utf8.encode(jsonEncode(json))));
      expect(Shops.all, ['main']);
      expect(File(p.join(dir.path, '..', 'escape')).existsSync(), isFalse);
    });

    test('who may sign in is not restored: the people on this phone stay', () async {
      final repo = StaffRepo();
      await repo.add(name: 'Old admin', role: Role.admin, pin: '1111');
      final bytes = await BackupService.create(); // carries the old admin
      await repo.clearAll();
      await repo.add(name: 'New admin', role: Role.admin, pin: '2222');
      final code = await RecoveryCode.issue();

      await BackupService.restore(bytes);

      expect((await repo.list()).map((u) => u.name), ['New admin'],
          reason: 'a backup must not bring back old PINs');
      expect(await RecoveryCode.check(code), isTrue,
          reason: 'the recovery code stays with the people');
    });

    test('the people of each shop stay with that shop through a restore', () async {
      final repo = StaffRepo();
      await const BusinessProfile(name: 'Main', type: ShopType.other).save();
      final id = await Shops.create();
      await const BusinessProfile(name: 'Branch', type: ShopType.other).save(shop: id);
      await Shops.activate(id);
      await repo.add(name: 'Branch boss', role: Role.admin, pin: '9999');
      await Shops.activate(Shops.mainId);
      await repo.add(name: 'Main boss', role: Role.admin, pin: '1111');
      final bytes = await BackupService.create();

      await BackupService.restore(bytes);

      expect((await repo.list()).map((u) => u.name), ['Main boss']);
      await Shops.activate(id);
      expect((await repo.list()).map((u) => u.name), ['Branch boss']);
    });
  });
}
