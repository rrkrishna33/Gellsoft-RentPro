import '../core/device.dart';

/// How far the phone's date and time may differ from the real time before the
/// app asks for it to be corrected (network time keeps phones within seconds).
const clockTolerance = Duration(minutes: 5);

/// What the app remembers from the last time it spoke to the license server:
/// the server's time, and what the phone's clocks said at that moment.
class ClockReference {
  const ClockReference({
    required this.serverMs,
    required this.localMs,
    this.monoMs,
    this.bootCount,
  });

  /// The real time, from the signed license (milliseconds since 1970).
  final int serverMs;

  /// What the phone's own clock said when it was received.
  final int localMs;

  /// The phone's elapsed-time clock then; null when it could not be read.
  final int? monoMs;
  final int? bootCount;
}

enum ClockProblem {
  /// Nothing wrong, or nothing to compare with.
  none,

  /// The phone's time differs from the real time.
  changed,

  /// The phone restarted since the last check and Automatic date & time is
  /// off, so nothing can show whether the time was changed.
  unverifiable,
}

class ClockStatus {
  const ClockStatus({
    required this.problem,
    required this.now,
    required this.verified,
    this.skew,
  });

  final ClockProblem problem;

  /// The time to show and to trust: the real time when it could be worked out,
  /// otherwise the phone's.
  final DateTime now;

  /// True when [now] was worked out from the server's time.
  final bool verified;

  /// How far ahead (positive) or behind (negative) the phone is, if known.
  final Duration? skew;

  bool get ok => problem == ClockProblem.none;
}

/// Works out whether the phone's date and time can be trusted.
///
/// From the server's time at the last check, plus the time Android says has
/// passed since (a clock the user cannot move by changing the date), the real
/// time now is known. If the phone's clock disagrees, someone changed it.
/// After a restart that elapsed-time clock starts over, so the check cannot be
/// made; then the phone must be on Automatic date & time, or be checked online.
ClockStatus assessClock({
  required ClockReference? reference,
  required DateTime localNow,
  required ClockInfo? info,
}) {
  final ref = reference;
  if (ref == null || ref.monoMs == null || info == null) {
    // Nothing to compare with (never checked, or not an Android phone).
    return ClockStatus(
      problem: ClockProblem.none,
      now: localNow,
      verified: false,
    );
  }

  final sameBoot =
      ref.bootCount != null &&
      info.bootCount != null &&
      ref.bootCount == info.bootCount;

  if (sameBoot) {
    final expected = DateTime.fromMillisecondsSinceEpoch(
      ref.serverMs + (info.elapsedMs - ref.monoMs!),
    );
    final skew = localNow.difference(expected);
    return ClockStatus(
      problem: skew.abs() > clockTolerance
          ? ClockProblem.changed
          : ClockProblem.none,
      now: expected,
      verified: true,
      skew: skew,
    );
  }

  return ClockStatus(
    problem: info.autoTime == false
        ? ClockProblem.unverifiable
        : ClockProblem.none,
    now: localNow,
    verified: false,
  );
}
