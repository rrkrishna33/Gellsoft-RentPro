import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Slows down guessing of the app-lock PIN.
///
/// The first [freeAttempts] - 1 wrong PINs cost nothing. From the 5th wrong
/// attempt on, the lock screen refuses input for 30 seconds, doubling with
/// every further wrong PIN up to 15 minutes. The count is saved, so closing
/// and reopening the app does not reset it; a correct PIN does.
class PinLockout {
  PinLockout({this.failures = 0, this.lockedUntil});

  static const freeAttempts = 5;
  static const baseDelay = Duration(seconds: 30);
  static const maxDelay = Duration(minutes: 15);

  static const _failKey = 's_fail';
  static const _untilKey = 's_lockuntil';

  int failures;
  DateTime? lockedUntil;

  Duration remaining(DateTime now) {
    final until = lockedUntil;
    if (until == null) return Duration.zero;
    final d = until.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  bool isLocked(DateTime now) => remaining(now) > Duration.zero;

  /// Call after a wrong PIN.
  void recordFailure(DateTime now) {
    failures++;
    if (failures < freeAttempts) return;
    final doublings = min(failures - freeAttempts, 10);
    var delay = baseDelay * (1 << doublings);
    if (delay > maxDelay) delay = maxDelay;
    lockedUntil = now.add(delay);
  }

  /// Call after a correct PIN.
  void reset() {
    failures = 0;
    lockedUntil = null;
  }

  static Future<PinLockout> load() async {
    final sp = await SharedPreferences.getInstance();
    final until = sp.getInt(_untilKey);
    return PinLockout(
      failures: sp.getInt(_failKey) ?? 0,
      lockedUntil: until == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(until),
    );
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_failKey, failures);
    final until = lockedUntil;
    if (until == null) {
      await sp.remove(_untilKey);
    } else {
      await sp.setInt(_untilKey, until.millisecondsSinceEpoch);
    }
  }
}
