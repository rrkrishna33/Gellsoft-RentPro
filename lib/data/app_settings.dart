import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferences that are not part of the shop profile.
class AppSettings {
  /// PINs are stored as salted PBKDF2-HMAC-SHA256: `v2:<rounds>:<hex>`.
  static const _pinIterations = 10000;

  static String hashPin(String pin, String salt) =>
      'v2:$_pinIterations:${pbkdf2Hex(pin, salt, _pinIterations)}';

  /// PBKDF2 (RFC 8018) with HMAC-SHA256 and a 32-byte result, as hex.
  static String pbkdf2Hex(String password, String salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(password));
    var u = hmac.convert([...utf8.encode(salt), 0, 0, 0, 1]).bytes;
    final t = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    return t.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String newSalt() {
    final r = Random.secure();
    return base64Url.encode(List.generate(16, (_) => r.nextInt(256)));
  }

  /// Compares without stopping at the first difference.
  static bool _sameText(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Whether [pin] matches a [hash] made by [hashPin].
  static bool verifyPin(String pin, String hash, String salt) {
    if (hash.isEmpty || !hash.startsWith('v2:')) return false;
    final parts = hash.split(':');
    final rounds = parts.length == 3 ? int.tryParse(parts[1]) : null;
    // A damaged value must not make the check run for ages.
    if (rounds == null || rounds < 1 || rounds > 200000) return false;
    return _sameText(pbkdf2Hex(pin, salt, rounds), parts[2]);
  }

  final String language; // en | ta
  final ThemeMode themeMode;

  const AppSettings({this.language = 'en', this.themeMode = ThemeMode.dark});

  AppSettings copyWith({String? language, ThemeMode? themeMode}) => AppSettings(
    language: language ?? this.language,
    themeMode: themeMode ?? this.themeMode,
  );

  static Future<AppSettings> load() async {
    final sp = await SharedPreferences.getInstance();
    return AppSettings(
      language: sp.getString('s_lang') ?? 'en',
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == sp.getString('s_theme'),
        orElse: () => ThemeMode.dark,
      ),
    );
  }
}

class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => AppSettings.load();

  Future<void> setLanguage(String code) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('s_lang', code);
    state = AsyncData((state.valueOrNull ?? const AppSettings()).copyWith(
      language: code,
    ));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('s_theme', mode.name);
    state = AsyncData((state.valueOrNull ?? const AppSettings()).copyWith(
      themeMode: mode,
    ));
  }
}

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
      AppSettingsNotifier.new,
    );

/// Whether Home hides the money amounts (the eye button).
class HideAmountsNotifier extends Notifier<bool> {
  @override
  bool build() {
    SharedPreferences.getInstance().then((sp) {
      state = sp.getBool('s_hideamounts') ?? false;
    });
    return false;
  }

  Future<void> toggle() async {
    state = !state;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('s_hideamounts', state);
  }
}

final hideAmountsProvider = NotifierProvider<HideAmountsNotifier, bool>(
  HideAmountsNotifier.new,
);
