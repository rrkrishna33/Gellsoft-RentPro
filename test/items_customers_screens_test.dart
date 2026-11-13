import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/theme.dart';
import 'package:gellsoft_rentpro/data/business_profile.dart';
import 'package:gellsoft_rentpro/core/constants.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:gellsoft_rentpro/features/customers/customers_screen.dart';
import 'package:gellsoft_rentpro/features/items/items_screen.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-ins, so the screens are tested without a database.
class _MemItems extends ItemRepo {
  final rows = <RentItem>[];
  int _next = 1;

  @override
  Future<List<RentItem>> list({
    String query = '',
    bool includeRetired = false,
  }) async => [
    for (final i in rows)
      if ((includeRetired || i.status != ItemStatus.retired) &&
          (query.isEmpty ||
              i.name.toLowerCase().contains(query.toLowerCase())))
        i,
  ];

  @override
  Future<int> save(RentItem item) async {
    if (item.id == null) {
      final id = _next++;
      rows.add(
        RentItem(
          id: id,
          uuid: 'u$id',
          name: item.name.trim(),
          category: item.category.trim(),
          size: item.size,
          rateType: item.rateType,
          rate: item.rate,
          deposit: item.deposit,
          quantity: item.quantity,
          notes: item.notes,
          status: item.status,
          createdAt: item.createdAt,
        ),
      );
      return id;
    }
    rows[rows.indexWhere((r) => r.id == item.id)] = item;
    return item.id!;
  }

  @override
  Future<void> delete(int id) async => rows.removeWhere((r) => r.id == id);

  @override
  Future<List<String>> categoriesInUse() async => [
    for (final r in rows)
      if (r.category.isNotEmpty) r.category,
  ];
}

class _MemCustomers extends CustomerRepo {
  final rows = <Customer>[];
  int _next = 1;

  @override
  Future<List<Customer>> list({String query = ''}) async => [
    for (final c in rows)
      if (query.isEmpty || c.name.toLowerCase().contains(query.toLowerCase())) c,
  ];

  @override
  Future<Customer?> byPhone(String phone, {int? exceptId}) async {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.length < 6) return null;
    for (final c in rows) {
      if (c.id != exceptId && c.phone.replaceAll(RegExp(r'\D'), '') == d) {
        return c;
      }
    }
    return null;
  }

  @override
  Future<int> save(Customer c) async {
    if (c.id == null) {
      final id = _next++;
      rows.add(
        Customer(
          id: id,
          uuid: 'c$id',
          name: c.name.trim(),
          phone: c.phone.trim(),
          address: c.address,
          idNote: c.idNote,
          notes: c.notes,
          createdAt: c.createdAt,
        ),
      );
      return id;
    }
    rows[rows.indexWhere((r) => r.id == c.id)] = c;
    return c.id!;
  }

  @override
  Future<void> delete(int id) async => rows.removeWhere((r) => r.id == id);
}

/// A tall screen, so a whole form is built and visible at once.
void tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

Widget host(
  Widget child, {
  ItemRepo? items,
  CustomerRepo? customers,
  BusinessProfile shop = const BusinessProfile(
    name: 'Shop',
    type: ShopType.costume,
  ),
}) => ProviderScope(
      overrides: [
        itemRepoProvider.overrideWithValue(items ?? _MemItems()),
        customerRepoProvider.overrideWithValue(customers ?? _MemCustomers()),
        profileProvider.overrideWith(() => _FixedProfile(shop)),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child)),
    );

class _FixedProfile extends ProfileNotifier {
  _FixedProfile(this.p);
  final BusinessProfile p;
  @override
  Future<BusinessProfile?> build() async => p;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => Lang.current = AppLanguage.en);

  testWidgets('add an item, see it in the list, search it, edit it', (t) async {
    tall(t);
    final repo = _MemItems();
    await t.pumpWidget(host(const ItemsScreen(), items: repo));
    await settle(t);
    expect(find.text('Add the things you rent out, with their rate.'),
        findsOneWidget);

    await t.tap(find.text('Add item'));
    await settle(t);

    // nothing typed: refused
    await t.scrollUntilVisible(
      find.text('Save'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text('Save'));
    await settle(t);
    expect(find.text('Enter the item name'), findsOneWidget);
    expect(find.text('Enter the rent'), findsOneWidget);

    await t.enterText(find.widgetWithText(TextFormField, 'Item name'), 'Red sherwani');
    await t.enterText(
      find.widgetWithText(TextFormField, 'Rent for one piece (₹)'),
      '2,500',
    );
    await t.enterText(
      find.widgetWithText(TextFormField, 'Deposit for one piece (₹)'),
      '5000',
    );
    await t.enterText(find.widgetWithText(TextFormField, 'Quantity'), '10');
    // the shop type offers its categories in a drop-down list
    await t.scrollUntilVisible(
      find.byType(DropdownButtonFormField<String>),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await settle(t);
    await t.tap(find.text('Sherwani').last);
    await settle(t);
    await t.scrollUntilVisible(
      find.text('Save'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text('Save'));
    await settle(t);

    expect(repo.rows.single.name, 'Red sherwani');
    expect(repo.rows.single.rate, 2500);
    expect(repo.rows.single.deposit, 5000);
    expect(repo.rows.single.category, 'Sherwani');
    expect(repo.rows.single.quantity, 10);
    expect(find.textContaining('10 pieces'), findsOneWidget);
    expect(find.text('Red sherwani'), findsOneWidget);
    expect(find.textContaining('2,500'), findsOneWidget);
    expect(find.text('an event'), findsOneWidget);

    // search
    await t.enterText(find.byType(TextField).first, 'zzz');
    await settle(t);
    expect(find.text('No item matches your search.'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'red');
    await settle(t);
    expect(find.text('Red sherwani'), findsOneWidget);

    // edit: mark in repair
    await t.tap(find.text('Red sherwani'));
    await settle(t);
    expect(find.text('Edit item'), findsOneWidget);
    await t.tap(find.byType(DropdownButtonFormField<ItemStatus>));
    await settle(t);
    await t.tap(find.text('In repair').last);
    await settle(t);
    await t.scrollUntilVisible(
      find.text('Save'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text('Save'));
    await settle(t);
    expect(repo.rows.single.status, ItemStatus.repair);
    expect(find.text('In repair'), findsOneWidget, reason: 'shown on the tile');
  });

  testWidgets('a category can be typed instead of chosen from the list', (t) async {
    tall(t);
    final repo = _MemItems();
    await t.pumpWidget(host(const ItemsScreen(), items: repo));
    await settle(t);
    await t.tap(find.text('Add item'));
    await settle(t);
    await t.enterText(find.widgetWithText(TextFormField, 'Item name'), 'Silk veil');
    await t.enterText(
      find.widgetWithText(TextFormField, 'Rent for one piece (₹)'),
      '300',
    );
    // no text box until "type my own" is chosen
    expect(find.widgetWithText(TextFormField, 'Category name'), findsNothing);
    await t.scrollUntilVisible(
      find.byType(DropdownButtonFormField<String>),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await settle(t);
    // the list holds this kind of shop's categories, then the typing choice
    expect(find.text('Lehenga'), findsWidgets);
    expect(find.text('Footwear'), findsWidgets);
    expect(find.text('Sound system'), findsNothing,
        reason: 'a costume shop is not offered equipment categories');
    await t.tap(find.text('Type my own category...').last);
    await settle(t);
    await t.enterText(
      find.widgetWithText(TextFormField, 'Category name'),
      'Bridal veils',
    );
    await t.scrollUntilVisible(
      find.text('Save'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text('Save'));
    await settle(t);
    expect(repo.rows.single.category, 'Bridal veils');
    expect(repo.rows.single.quantity, 1, reason: 'one piece unless said');
  });

  testWidgets('a makeup artist adds services: no quantity, size or deposit', (t) async {
    tall(t);
    final repo = _MemItems();
    await t.pumpWidget(
      host(
        const ItemsScreen(),
        items: repo,
        shop: const BusinessProfile(name: 'Glow', type: ShopType.makeup),
      ),
    );
    await settle(t);
    expect(find.text('Services'), findsWidgets);
    expect(find.text('Add the services you offer, with their price.'),
        findsOneWidget);
    await t.tap(find.text('Add service'));
    await settle(t);
    expect(find.text('Service name'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Quantity'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Size (optional)'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Deposit for one piece (₹)'),
        findsNothing);
    await t.enterText(find.widgetWithText(TextFormField, 'Service name'), 'Bridal makeup');
    await t.enterText(find.widgetWithText(TextFormField, 'Price (₹)'), '15000');
    await t.scrollUntilVisible(
      find.byType(DropdownButtonFormField<String>),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await settle(t);
    await t.tap(find.text('Bridal makeup').last);
    await settle(t);
    await t.scrollUntilVisible(
      find.text('Save'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text('Save'));
    await settle(t);
    final saved = repo.rows.single;
    expect(saved.name, 'Bridal makeup');
    expect(saved.category, 'Bridal makeup');
    expect(saved.rate, 15000);
    expect(saved.quantity, 1);
    expect(saved.deposit, 0);
    expect(find.text('a booking'), findsOneWidget);
  });

  testWidgets('removing an item asks first', (t) async {
    tall(t);
    final repo = _MemItems();
    await repo.save(RentItem(name: 'Gown', rate: 800, createdAt: DateTime(2027)));
    await t.pumpWidget(host(const ItemsScreen(), items: repo));
    await settle(t);
    await t.tap(find.text('Gown'));
    await settle(t);
    await t.tap(find.byIcon(Icons.delete_outline));
    await settle(t);
    expect(find.text('Remove this item?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await settle(t);
    expect(repo.rows.length, 1);
    await t.tap(find.byIcon(Icons.delete_outline));
    await settle(t);
    await t.tap(find.widgetWithText(FilledButton, 'Remove'));
    await settle(t);
    expect(repo.rows, isEmpty);
    expect(find.text('Add the things you rent out, with their rate.'),
        findsOneWidget);
  });

  testWidgets('add a customer; the same phone asks before saving again', (
    t,
  ) async {
    tall(t);
    final repo = _MemCustomers();
    await t.pumpWidget(host(const CustomersScreen(), customers: repo));
    await settle(t);
    expect(find.text('Add your customers to book items for them.'),
        findsOneWidget);

    Future<void> add(String name, String phone) async {
      await t.tap(find.text('Add customer'));
      await settle(t);
      await t.enterText(find.widgetWithText(TextFormField, 'Customer name'), name);
      await t.enterText(find.widgetWithText(TextFormField, 'Phone'), phone);
      await t.scrollUntilVisible(
      find.text('Save'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
      await t.tap(find.text('Save'));
      await settle(t);
    }

    // an empty name is refused
    await t.tap(find.text('Add customer'));
    await settle(t);
    await t.scrollUntilVisible(
      find.text('Save'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text('Save'));
    await settle(t);
    expect(find.text('Enter the customer name'), findsOneWidget);
    await t.pageBack();
    await settle(t);

    await add('Anu', '98765 43210');
    expect(repo.rows.single.name, 'Anu');
    expect(find.text('Anu'), findsOneWidget);

    // same number, different spacing
    await add('Anu again', '98765-43210');
    expect(find.text('Same phone number'), findsOneWidget);
    expect(find.textContaining('Anu already has'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await settle(t);
    expect(repo.rows.length, 1, reason: 'cancelled: nothing saved');
    await t.scrollUntilVisible(
      find.text('Save'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text('Save'));
    await settle(t);
    await t.tap(find.text('Save anyway'));
    await settle(t);
    expect(repo.rows.length, 2);
  });

  testWidgets('Tamil labels show on the item form', (t) async {
    tall(t);
    Lang.current = AppLanguage.ta;
    await t.pumpWidget(host(const ItemsScreen()));
    await settle(t);
    expect(find.text('பொருளைச் சேர்'), findsOneWidget);
    await t.tap(find.text('பொருளைச் சேர்'));
    await settle(t);
    expect(find.text('பொருளின் பெயர்'), findsOneWidget);
    expect(find.text('நிகழ்வுக்கு'), findsOneWidget);
  });
}
