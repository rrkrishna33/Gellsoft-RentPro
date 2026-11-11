import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferences that are not part of the shop profile.
class AppSettings {
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
