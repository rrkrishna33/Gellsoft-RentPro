import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;
  final items = ItemRepo();
  final customers = CustomerRepo();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rentpro_repo');
    AppDatabase.pathOverride = '${dir.path}/test.db';
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AppDatabase.pathOverride = null;
    await dir.delete(recursive: true);
  });

  RentItem item(
    String name, {
    String category = '',
    String size = '',
    double rate = 1000,
    ItemStatus status = ItemStatus.active,
  }) => RentItem(
    name: name,
    category: category,
    size: size,
    rate: rate,
    status: status,
    createdAt: DateTime(2027),
  );

  group('items', () {
    test('save, read back and change', () async {
      final id = await items.save(
        item('Red sherwani', category: 'Sherwani', size: 'L', rate: 2500)
            .copyWith(deposit: 5000, rateType: RateType.day, notes: ' gold ',),
      );
      final got = (await items.get(id))!;
      expect(got.name, 'Red sherwani');
      expect(got.rate, 2500);
      expect(got.deposit, 5000);
      expect(got.rateType, RateType.day);
      expect(got.notes, 'gold', reason: 'text is trimmed');
      expect(got.uuid, isNotEmpty);

      await items.save(got.copyWith(rate: 3000, status: ItemStatus.repair));
      final again = (await items.get(id))!;
      expect(again.rate, 3000);
      expect(again.status, ItemStatus.repair);
      expect(again.uuid, got.uuid, reason: 'the id of the record never changes');
    });

    test('search matches name, category and size; % is literal', () async {
      await items.save(item('Blue gown', category: 'Gown', size: 'M'));
      await items.save(item('Red lehenga', category: 'Lehenga', size: 'XL'));
      await items.save(item('50% off banner', category: 'Decor'));
      await items.save(item('50x banner', category: 'Decor'));
      expect((await items.list(query: 'gown')).map((i) => i.name), ['Blue gown']);
      expect((await items.list(query: 'lehe')).length, 1);
      expect((await items.list(query: 'xl')).single.name, 'Red lehenga');
      expect(
        (await items.list(query: '50%')).map((i) => i.name),
        ['50% off banner'],
      );
      expect((await items.list(query: 'nothing')), isEmpty);
    });

    test('retired and removed items are hidden; repair stays listed', () async {
      final a = await items.save(item('Active'));
      final b = await items.save(item('Repair', status: ItemStatus.repair));
      final c = await items.save(item('Retired', status: ItemStatus.retired));
      final d = await items.save(item('Gone'));
      await items.delete(d);
      expect((await items.list()).map((i) => i.id), [a, b]);
      expect((await items.list(includeRetired: true)).map((i) => i.id).toSet(),
          {a, b, c});
      expect(await items.get(d), isNull);
      await items.setStatus(a, ItemStatus.retired);
      expect((await items.list()).map((i) => i.id), [b]);
    });

    test('sorted by category then name, ignoring case', () async {
      await items.save(item('b item', category: 'Zeta'));
      await items.save(item('A item', category: 'zeta'));
      await items.save(item('Z item', category: 'Alpha'));
      expect((await items.list()).map((i) => i.name), [
        'Z item',
        'A item',
        'b item',
      ]);
    });

    test('categories in use are listed once', () async {
      await items.save(item('a', category: 'Saree'));
      await items.save(item('b', category: 'Saree'));
      await items.save(item('c', category: 'Gown'));
      await items.save(item('d'));
      expect(await items.categoriesInUse(), ['Gown', 'Saree']);
    });

    test('bookable only when available', () {
      expect(ItemStatus.active.bookable, isTrue);
      expect(ItemStatus.repair.bookable, isFalse);
      expect(ItemStatus.retired.bookable, isFalse);
    });
  });

  group('customers', () {
    Customer person(String name, {String phone = '', String address = ''}) =>
        Customer(
          name: name,
          phone: phone,
          address: address,
          createdAt: DateTime(2027),
        );

    test('save, read back and change', () async {
      final id = await customers.save(
        person('Anu', phone: '98765 43210').copyWith(idNote: 'Aadhaar 1234'),
      );
      final got = (await customers.get(id))!;
      expect(got.name, 'Anu');
      expect(got.idNote, 'Aadhaar 1234');
      await customers.save(got.copyWith(address: 'Madurai'));
      expect((await customers.get(id))!.address, 'Madurai');
    });

    test('search finds by name, phone and address; sorted by name', () async {
      await customers.save(person('bala', phone: '9000000001'));
      await customers.save(person('Anu', phone: '9000000002', address: 'Sivakasi'));
      expect((await customers.list()).map((c) => c.name), ['Anu', 'bala']);
      expect((await customers.list(query: '0002')).single.name, 'Anu');
      expect((await customers.list(query: 'sivak')).single.name, 'Anu');
      expect((await customers.list(query: 'BAL')).single.name, 'bala');
    });

    test('a removed customer leaves the list', () async {
      final id = await customers.save(person('Anu'));
      await customers.delete(id);
      expect(await customers.list(), isEmpty);
      expect(await customers.get(id), isNull);
    });

    test('finds a twin by phone, ignoring spaces and dashes', () async {
      final id = await customers.save(person('Anu', phone: '98765-43210'));
      expect((await customers.byPhone('98765 43210'))?.name, 'Anu');
      expect(await customers.byPhone('98765 43210', exceptId: id), isNull,
          reason: 'editing the same person is not a duplicate');
      expect(await customers.byPhone('12345'), isNull,
          reason: 'too short to compare');
      expect(await customers.byPhone('90000 00000'), isNull);
    });
  });
}
