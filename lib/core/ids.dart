import 'dart:math';

final _rng = Random.secure();

/// A random id that is unique across phones (used for the `uuid` columns).
String newUuid() {
  String hex(int n) =>
      List.generate(n, (_) => _rng.nextInt(16).toRadixString(16)).join();
  return '${hex(8)}-${hex(4)}-4${hex(3)}-${(8 + _rng.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';
}
