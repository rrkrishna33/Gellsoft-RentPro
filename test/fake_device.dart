import 'package:gellsoft_rentpro/core/device.dart';

/// A pretend phone for tests: its clocks and id are whatever the test sets.
class FakeDevice implements DeviceInfo {
  FakeDevice({
    this.id =
        'ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12',
    this.info = const ClockInfo(
      elapsedMs: 1000000,
      bootCount: 7,
      autoTime: true,
    ),
  });

  /// The scrambled phone id, or null for a phone that will not say.
  String? id;

  /// What Android reports about its clocks, or null (not an Android phone).
  ClockInfo? info;

  int settingsOpened = 0;

  /// Lets time pass on the phone's elapsed-time clock (the one a user cannot
  /// change by setting the date).
  void pass(Duration d) {
    final i = info;
    if (i == null) return;
    info = ClockInfo(
      elapsedMs: i.elapsedMs + d.inMilliseconds,
      bootCount: i.bootCount,
      autoTime: i.autoTime,
    );
  }

  /// The phone restarts: the elapsed-time clock starts over, the count goes up.
  void restart() {
    final i = info;
    if (i == null) return;
    info = ClockInfo(
      elapsedMs: 5000,
      bootCount: (i.bootCount ?? 0) + 1,
      autoTime: i.autoTime,
    );
  }

  void setAutoTime(bool? on) {
    final i = info;
    if (i == null) return;
    info = ClockInfo(
      elapsedMs: i.elapsedMs,
      bootCount: i.bootCount,
      autoTime: on,
    );
  }

  @override
  Future<ClockInfo?> clock() async => info;

  @override
  Future<String?> deviceId() async => id;

  @override
  Future<void> openDateSettings() async => settingsOpened++;
}
