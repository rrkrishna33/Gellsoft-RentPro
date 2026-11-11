import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What Android says about its clocks, none of which the user can change by
/// setting the date: [elapsedMs] counts time since the phone started (even
/// while asleep), and [bootCount] says how many times it has started.
class ClockInfo {
  const ClockInfo({required this.elapsedMs, this.bootCount, this.autoTime});

  final int elapsedMs;

  /// null when the phone does not say.
  final int? bootCount;

  /// Whether "Automatic date & time" is on; null when the phone does not say.
  final bool? autoTime;
}

/// The few things the app asks the phone itself. Faked in tests.
abstract class DeviceInfo {
  Future<ClockInfo?> clock();

  /// A one-way scrambled id of this phone, or null if it cannot be read.
  Future<String?> deviceId();

  Future<void> openDateSettings();
}

/// A phone's Android id, scrambled so the real value is never sent: the same
/// phone always gives the same text, but the text cannot be turned back.
String scrambleDeviceId(String androidId) =>
    sha256.convert(utf8.encode('gellsoft-rentpro|$androidId')).toString();

class PlatformDeviceInfo implements DeviceInfo {
  static const _channel = MethodChannel('gellsoft/device');

  @override
  Future<ClockInfo?> clock() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('clockInfo');
      if (m == null) return null;
      final elapsed = m['elapsedMs'];
      if (elapsed is! int) return null;
      final boot = m['bootCount'];
      final auto = m['autoTime'];
      return ClockInfo(
        elapsedMs: elapsed,
        bootCount: (boot is int && boot >= 0) ? boot : null,
        autoTime: auto is bool ? auto : null,
      );
    } on MissingPluginException {
      return null; // not Android (or the plugin is not there)
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<String?> deviceId() async {
    try {
      final id = await _channel.invokeMethod<String>('deviceId');
      if (id == null || id.isEmpty) return null;
      return scrambleDeviceId(id);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> openDateSettings() async {
    try {
      await _channel.invokeMethod<void>('openDateSettings');
    } on MissingPluginException {
      // nothing to open
    } on PlatformException {
      // the settings screen could not be opened; the user can do it by hand
    }
  }
}

final deviceInfoProvider = Provider<DeviceInfo>((_) => PlatformDeviceInfo());
