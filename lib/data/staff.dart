import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../core/ids.dart';
import 'app_settings.dart';
import 'database.dart';
import 'shops.dart';

/// What a person may do in the app. Screens ask for one of these instead of
/// checking a role, so the rules live in one place ([Role.can]).
enum Permission {
  /// Make and change bookings, hand items out and take them back, make
  /// invoices and receipts.
  book,

  /// Take a payment, a deposit or give a refund.
  collectPayments,

  /// Give a discount on a booking.
  giveDiscount,

  /// Add, change and remove items, their rates and quantities.
  editItems,

  /// Change or remove customers (adding one while booking is always allowed).
  editCustomers,

  /// Cancel a booking or an invoice.
  cancelBookings,

  /// Money totals on Home, and the reports.
  seeReports,

  /// The files for the accountant: GST returns and the CSV exports.
  exportData,

  /// Shop details, billing and GST, backup and restore, the shops list and
  /// the Pro screen.
  settings,

  /// Add, change and remove people.
  manageStaff,
}

enum Role {
  admin,
  staff,
  cashier;

  /// An unknown stored value gets the least access, never the most.
  static Role fromCode(String? code) =>
      values.firstWhere((r) => r.name == code, orElse: () => Role.cashier);

  bool can(Permission p) => _grants[this]!.contains(p);

  static const _grants = <Role, Set<Permission>>{
    // the owner: everything
    Role.admin: {...Permission.values},
    // a manager or senior: runs the shop day to day, but no accountant files,
    // cancelling, settings or other people
    Role.staff: {
      Permission.book,
      Permission.collectPayments,
      Permission.giveDiscount,
      Permission.editItems,
      Permission.editCustomers,
      Permission.seeReports,
    },
    // the counter: bookings and payments, nothing else
    Role.cashier: {Permission.book, Permission.collectPayments},
  };
}

class StaffUser {
  const StaffUser({
    this.id,
    required this.uuid,
    required this.name,
    required this.role,
    required this.pinHash,
    required this.pinSalt,
    this.active = true,
    required this.createdAt,
  });

  final int? id;
  final String uuid;
  final String name;
  final Role role;
  final String pinHash;
  final String pinSalt;
  final bool active;
  final DateTime createdAt;

  bool checkPin(String pin) => AppSettings.verifyPin(pin, pinHash, pinSalt);

  factory StaffUser.fromMap(Map<String, Object?> m) => StaffUser(
    id: m['id'] as int,
    uuid: m['uuid'] as String,
    name: m['name'] as String,
    role: Role.fromCode(m['role'] as String?),
    pinHash: m['pin_hash'] as String,
    pinSalt: m['pin_salt'] as String,
    active: m['active'] == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
  );
}

/// Why a change to the people list was refused.
enum StaffError {
  /// A name is needed, and two people cannot share one.
  nameTaken,
  nameEmpty,

  /// There must always be an active Admin who can get back in.
  lastAdmin,
  badPin,
}

class StaffException implements Exception {
  const StaffException(this.error);
  final StaffError error;
  @override
  String toString() => 'StaffException(${error.name})';
}

final _pinPattern = RegExp(r'^\d{4,6}$');

/// The people of the open shop (each shop has its own).
class StaffRepo {
  Future<Database> get _db => AppDatabase.instance.db;

  /// Everyone, Admins first.
  Future<List<StaffUser>> list() async {
    final d = await _db;
    final rows = await d.query('staff_users', orderBy: 'id');
    final all = rows.map(StaffUser.fromMap).toList();
    all.sort((a, b) {
      final byRole = a.role.index.compareTo(b.role.index);
      return byRole != 0
          ? byRole
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return all;
  }

  Future<void> _checkName(
    DatabaseExecutor d,
    String name, {
    String? exceptUuid,
  }) async {
    final n = name.trim();
    if (n.isEmpty) throw const StaffException(StaffError.nameEmpty);
    final rows = await d.query(
      'staff_users',
      where: 'LOWER(name) = ?',
      whereArgs: [n.toLowerCase()],
    );
    if (rows.any((r) => r['uuid'] != exceptUuid)) {
      throw const StaffException(StaffError.nameTaken);
    }
  }

  Future<int> _activeAdmins(DatabaseExecutor d, {String? except}) async {
    final rows = await d.query(
      'staff_users',
      where: "role = 'admin' AND active = 1",
    );
    return rows.where((r) => r['uuid'] != except).length;
  }

  Future<StaffUser> add({
    required String name,
    required Role role,
    required String pin,
  }) async {
    if (!_pinPattern.hasMatch(pin)) {
      throw const StaffException(StaffError.badPin);
    }
    final d = await _db;
    return d.transaction((txn) async {
      await _checkName(txn, name);
      final salt = AppSettings.newSalt();
      final uuid = newUuid();
      final now = DateTime.now();
      final hash = AppSettings.hashPin(pin, salt);
      final id = await txn.insert('staff_users', {
        'uuid': uuid,
        'name': name.trim(),
        'role': role.name,
        'pin_hash': hash,
        'pin_salt': salt,
        'active': 1,
        'created_at': now.millisecondsSinceEpoch,
      });
      return StaffUser(
        id: id,
        uuid: uuid,
        name: name.trim(),
        role: role,
        pinHash: hash,
        pinSalt: salt,
        createdAt: now,
      );
    });
  }

  /// Changes a person's name, role or whether they can sign in. The last
  /// active Admin cannot be demoted or switched off.
  Future<void> update(
    String uuid, {
    String? name,
    Role? role,
    bool? active,
  }) async {
    final d = await _db;
    await d.transaction((txn) async {
      final rows = await txn.query(
        'staff_users',
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      if (rows.isEmpty) return;
      final cur = StaffUser.fromMap(rows.first);
      final newRole = role ?? cur.role;
      final newActive = active ?? cur.active;
      if (name != null) await _checkName(txn, name, exceptUuid: uuid);
      final staysAdmin = newRole == Role.admin && newActive;
      if (cur.role == Role.admin &&
          cur.active &&
          !staysAdmin &&
          await _activeAdmins(txn, except: uuid) == 0) {
        throw const StaffException(StaffError.lastAdmin);
      }
      await txn.update(
        'staff_users',
        {
          if (name != null) 'name': name.trim(),
          'role': newRole.name,
          'active': newActive ? 1 : 0,
        },
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
    });
  }

  Future<void> setPin(String uuid, String pin) async {
    if (!_pinPattern.hasMatch(pin)) {
      throw const StaffException(StaffError.badPin);
    }
    final salt = AppSettings.newSalt();
    final d = await _db;
    await d.update(
      'staff_users',
      {'pin_hash': AppSettings.hashPin(pin, salt), 'pin_salt': salt},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  /// Removes a person. Their past bookings keep their name. The last active
  /// Admin cannot be removed.
  Future<void> remove(String uuid) async {
    final d = await _db;
    await d.transaction((txn) async {
      final rows = await txn.query(
        'staff_users',
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      if (rows.isEmpty) return;
      final cur = StaffUser.fromMap(rows.first);
      if (cur.role == Role.admin &&
          cur.active &&
          await _activeAdmins(txn, except: uuid) == 0) {
        throw const StaffException(StaffError.lastAdmin);
      }
      await txn.delete('staff_users', where: 'uuid = ?', whereArgs: [uuid]);
    });
  }

  /// Turns staff logins off: everyone is removed and the app is open again.
  Future<void> clearAll() async {
    final d = await _db;
    await d.delete('staff_users');
  }
}

/// A one-time code that gets an Admin back in after a forgotten PIN. Shown
/// once when staff logins are turned on; only a hash is kept. Each shop has
/// its own code, like its own people.
class RecoveryCode {
  static String get _hashKey => Shops.key('s', 'recovhash');
  static String get _saltKey => Shops.key('s', 'recovsalt');

  /// Eight digits, shown as `1234 5678`.
  static String _make() {
    final r = Random.secure();
    final digits = List.generate(8, (_) => r.nextInt(10)).join();
    return '${digits.substring(0, 4)} ${digits.substring(4)}';
  }

  static String _plain(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// Makes a new code, keeps its hash, and returns it to show.
  static Future<String> issue() async {
    final code = _make();
    final salt = AppSettings.newSalt();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_saltKey, salt);
    await sp.setString(_hashKey, AppSettings.hashPin(_plain(code), salt));
    return code;
  }

  static Future<bool> check(String input) async {
    final sp = await SharedPreferences.getInstance();
    final hash = sp.getString(_hashKey) ?? '';
    final salt = sp.getString(_saltKey) ?? '';
    final plain = _plain(input);
    return plain.length == 8 && AppSettings.verifyPin(plain, hash, salt);
  }

  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_hashKey);
    await sp.remove(_saltKey);
  }
}

final staffRepoProvider = Provider((_) => StaffRepo());

final staffUsersProvider = FutureProvider<List<StaffUser>>(
  (ref) => ref.watch(staffRepoProvider).list(),
);

/// Who is signed in. Survives an app restart (a language change) so the PIN
/// is not asked again straight after. Switching shops signs everyone out.
StaffUser? _sessionUser;

class SessionNotifier extends Notifier<StaffUser?> {
  @override
  StaffUser? build() {
    // Keep the signed-in person in step with the list: a changed role applies
    // at once, and someone removed or switched off is signed out.
    ref.listen(staffUsersProvider, (_, next) {
      final users = next.valueOrNull;
      final cur = state;
      if (users == null || cur == null) return;
      StaffUser? fresh;
      for (final u in users) {
        if (u.uuid == cur.uuid && u.active) fresh = u;
      }
      _set(fresh);
    });
    return _sessionUser;
  }

  void _set(StaffUser? u) {
    _sessionUser = u;
    state = u;
  }

  void login(StaffUser u) => _set(u);
  void logout() => _set(null);
}

final sessionProvider = NotifierProvider<SessionNotifier, StaffUser?>(
  SessionNotifier.new,
);

/// What the person using the app may do. With staff logins off nobody is
/// signed in and everything is allowed, exactly as before.
class Perms {
  const Perms(this.user);
  final StaffUser? user;

  bool can(Permission p) => user == null || user!.role.can(p);

  /// The signed-in person's name for "booked by", or '' when logins are off.
  String get name => user?.name ?? '';
}

final permsProvider = Provider<Perms>(
  (ref) => Perms(ref.watch(sessionProvider)),
);

/// Forgets who is signed in: on switching shops, and in tests.
void forgetSignedInPerson() => _sessionUser = null;
