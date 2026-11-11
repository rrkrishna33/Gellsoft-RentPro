import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite database. Dates are stored as epoch milliseconds (whole days
/// at local midnight for booking dates). The main tables carry sync columns
/// so a cloud layer can be added later without a schema rewrite:
///   uuid       - globally unique id
///   updated_at - epoch millis of last change
///   deleted    - soft delete flag
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();
  Database? _db;
  Future<Database>? _opening;

  /// File name used instead of the real one (tests point this at a temp file).
  @visibleForTesting
  static String? pathOverride;

  /// The open database. Callers that arrive while it is still opening wait for
  /// the same opening: two at once must never open two connections.
  Future<Database> get db async {
    final open = _db;
    if (open != null) return open;
    return _opening ??= _open().then(
      (d) {
        _db = d;
        _opening = null;
        return d;
      },
      onError: (Object e, StackTrace s) {
        _opening = null;
        throw e;
      },
    );
  }

  Future<String> get filePath async =>
      pathOverride ?? p.join(await getDatabasesPath(), 'gellsoft_rentpro.db');

  Future<Database> _open() async => openDatabase(
    await filePath,
    version: schemaVersion,
    onCreate: _onCreate,
    onUpgrade: _onUpgrade,
  );

  /// 1 = items, customers, bookings (with their items, payments and photos).
  /// 2 = GST: a rate and SAC/HSN on items, GSTIN and state on customers, tax on
  /// bookings and their lines, and invoices. A phone that already has a
  /// version 1 file from an earlier build gets exactly what it lacks (see
  /// [_migrateTo2]); a new install is made complete at once.
  static const schemaVersion = 2;

  /// Closes the connection; the next access reopens the file. Used by restore.
  Future<void> close() async {
    final pending = _opening;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // it never opened; nothing to close
      }
    }
    await _db?.close();
    _db = null;
  }

  Future<void> _onCreate(Database d, int v) async {
    await createV1(d);
  }

  Future<void> _onUpgrade(Database d, int from, int to) async {
    if (from < 2) await _migrateTo2(d);
  }

  /// Adds a column unless the table already has it.
  Future<void> _addColumn(
    DatabaseExecutor d,
    String table,
    String column,
    String definition,
  ) async {
    final have = (await d.rawQuery('PRAGMA table_info($table)'))
        .map((r) => r['name'])
        .toSet();
    if (!have.contains(column)) {
      await d.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  /// Brings a version 1 file up to the GST schema. The version 1 files that
  /// exist differ (the app was built several times before GST), so every
  /// column is checked first and only the missing ones are added. Nothing the
  /// shop has entered is changed or lost.
  @visibleForTesting
  Future<void> migrateTo2ForTest(Database d) => _migrateTo2(d);

  Future<void> _migrateTo2(Database d) async {
    await _addColumn(d, 'items', 'hsn', "TEXT NOT NULL DEFAULT ''");
    await _addColumn(d, 'items', 'gst_rate', 'REAL NOT NULL DEFAULT 0');
    await _addColumn(d, 'customers', 'gstin', "TEXT NOT NULL DEFAULT ''");
    await _addColumn(d, 'customers', 'state_code', "TEXT NOT NULL DEFAULT ''");
    await _addColumn(d, 'bookings', 'tax_total', 'REAL NOT NULL DEFAULT 0');
    await _addColumn(d, 'bookings', 'payable', 'REAL NOT NULL DEFAULT 0');
    await _addColumn(
      d,
      'booking_items',
      'rate_type',
      "TEXT NOT NULL DEFAULT 'event'",
    );
    await _addColumn(d, 'booking_items', 'amount', 'REAL NOT NULL DEFAULT 0');
    await _addColumn(d, 'booking_items', 'hsn', "TEXT NOT NULL DEFAULT ''");
    await _addColumn(d, 'booking_items', 'gst_rate', 'REAL NOT NULL DEFAULT 0');
    await _addColumn(d, 'booking_items', 'taxable', 'REAL NOT NULL DEFAULT 0');
    await _addColumn(d, 'booking_items', 'tax', 'REAL NOT NULL DEFAULT 0');
    // what an older booking owed: its rent less the discount (no GST then)
    await d.execute(
      'UPDATE bookings SET payable = rent_total - discount WHERE payable = 0',
    );
    await d.execute('UPDATE booking_items SET amount = rate WHERE amount = 0');
    await d.execute(
      'UPDATE booking_items SET taxable = amount WHERE taxable = 0',
    );
    await _createInvoiceTables(d);
  }

  @visibleForTesting
  Future<void> createV1(Database d) async {
    const sync = '''
      uuid TEXT NOT NULL UNIQUE,
      updated_at INTEGER NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0''';

    // What the shop rents out. rate_type: 'event' (flat per booking) or 'day'.
    // status: 'active', 'repair' (cannot be booked) or 'retired'.
    await d.execute('''
      CREATE TABLE items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        $sync,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT '',
        size TEXT NOT NULL DEFAULT '',
        rate_type TEXT NOT NULL DEFAULT 'event',
        rate REAL NOT NULL DEFAULT 0,
        deposit REAL NOT NULL DEFAULT 0,
        hsn TEXT NOT NULL DEFAULT '',
        gst_rate REAL NOT NULL DEFAULT 0,
        notes TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'active',
        created_at INTEGER NOT NULL
      )''');
    await d.execute('CREATE INDEX idx_items_name ON items(name)');

    await d.execute('''
      CREATE TABLE customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        $sync,
        name TEXT NOT NULL,
        phone TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        gstin TEXT NOT NULL DEFAULT '',
        state_code TEXT NOT NULL DEFAULT '',
        id_note TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )''');
    await d.execute('CREATE INDEX idx_customers_name ON customers(name)');

    // status: 'booked' -> 'picked_up' -> 'returned', or 'cancelled'.
    // event_date, pickup_date and return_date are whole days.
    await d.execute('''
      CREATE TABLE bookings(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        $sync,
        number INTEGER NOT NULL,
        customer_id INTEGER NOT NULL REFERENCES customers(id),
        event_date INTEGER NOT NULL,
        pickup_date INTEGER NOT NULL,
        return_date INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'booked',
        rent_total REAL NOT NULL DEFAULT 0,
        deposit_total REAL NOT NULL DEFAULT 0,
        discount REAL NOT NULL DEFAULT 0,
        tax_total REAL NOT NULL DEFAULT 0,
        payable REAL NOT NULL DEFAULT 0,
        notes TEXT NOT NULL DEFAULT '',
        remind_days INTEGER NOT NULL DEFAULT 2,
        created_at INTEGER NOT NULL
      )''');
    await d.execute(
      'CREATE INDEX idx_bookings_pickup ON bookings(pickup_date)',
    );
    await d.execute(
      'CREATE INDEX idx_bookings_return ON bookings(return_date)',
    );
    await d.execute(
      'CREATE INDEX idx_bookings_created ON bookings(created_at)',
    );

    // The items on a booking, with the rate they were booked at and what that
    // came to for the booked days (amount).
    await d.execute('''
      CREATE TABLE booking_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        booking_id INTEGER NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
        item_id INTEGER NOT NULL REFERENCES items(id),
        name TEXT NOT NULL,
        rate_type TEXT NOT NULL DEFAULT 'event',
        rate REAL NOT NULL DEFAULT 0,
        deposit REAL NOT NULL DEFAULT 0,
        amount REAL NOT NULL DEFAULT 0,
        hsn TEXT NOT NULL DEFAULT '',
        gst_rate REAL NOT NULL DEFAULT 0,
        taxable REAL NOT NULL DEFAULT 0,
        tax REAL NOT NULL DEFAULT 0
      )''');
    await d.execute(
      'CREATE INDEX idx_booking_items_item ON booking_items(item_id)',
    );
    await d.execute(
      'CREATE INDEX idx_booking_items_booking ON booking_items(booking_id)',
    );

    // kind: 'advance', 'balance', 'deposit' or 'refund' (money handed back).
    await d.execute('''
      CREATE TABLE payments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        booking_id INTEGER NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
        kind TEXT NOT NULL,
        amount REAL NOT NULL,
        mode TEXT NOT NULL DEFAULT 'cash',
        note TEXT NOT NULL DEFAULT '',
        paid_at INTEGER NOT NULL
      )''');
    await d.execute(
      'CREATE INDEX idx_payments_booking ON payments(booking_id)',
    );

    // stage: 'pickup', 'return' or 'other'. path is a file in the app folder.
    await d.execute('''
      CREATE TABLE booking_photos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        booking_id INTEGER NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
        stage TEXT NOT NULL DEFAULT 'other',
        path TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    await d.execute(
      'CREATE INDEX idx_booking_photos_booking ON booking_photos(booking_id)',
    );

    await _createInvoiceTables(d);
  }

  Future<void> _createInvoiceTables(DatabaseExecutor d) async {
    const sync = '''
      uuid TEXT NOT NULL UNIQUE,
      updated_at INTEGER NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0''';

    // An invoice (or plain bill, when GST is off) made from a booking. It
    // keeps its own copy of the customer and of every line, so it never
    // changes after it is issued. status: 'active' or 'cancelled'.
    await d.execute('''
      CREATE TABLE IF NOT EXISTS invoices(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        $sync,
        booking_id INTEGER NOT NULL REFERENCES bookings(id),
        prefix TEXT NOT NULL DEFAULT '',
        number INTEGER NOT NULL,
        invoice_date INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        cust_name TEXT NOT NULL DEFAULT '',
        cust_phone TEXT NOT NULL DEFAULT '',
        cust_address TEXT NOT NULL DEFAULT '',
        cust_gstin TEXT NOT NULL DEFAULT '',
        supply_state TEXT NOT NULL DEFAULT '',
        inter_state INTEGER NOT NULL DEFAULT 0,
        gst_enabled INTEGER NOT NULL DEFAULT 0,
        tax_inclusive INTEGER NOT NULL DEFAULT 0,
        discount REAL NOT NULL DEFAULT 0,
        taxable REAL NOT NULL DEFAULT 0,
        cgst REAL NOT NULL DEFAULT 0,
        sgst REAL NOT NULL DEFAULT 0,
        igst REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        event_date INTEGER NOT NULL,
        pickup_date INTEGER NOT NULL,
        return_date INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    await d.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoices_booking ON invoices(booking_id)',
    );
    await d.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoices_date ON invoices(invoice_date)',
    );

    await d.execute('''
      CREATE TABLE IF NOT EXISTS invoice_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        hsn TEXT NOT NULL DEFAULT '',
        rate_type TEXT NOT NULL DEFAULT 'event',
        rate REAL NOT NULL DEFAULT 0,
        days INTEGER NOT NULL DEFAULT 1,
        gst_rate REAL NOT NULL DEFAULT 0,
        taxable REAL NOT NULL DEFAULT 0,
        cgst REAL NOT NULL DEFAULT 0,
        sgst REAL NOT NULL DEFAULT 0,
        igst REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0
      )''');
    await d.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice ON invoice_items(invoice_id)',
    );
  }
}
