import 'ta.dart';

enum AppLanguage {
  en('en', 'English'),
  ta('ta', 'தமிழ்');

  const AppLanguage(this.code, this.label);
  final String code;
  final String label;

  static AppLanguage fromCode(String? code) =>
      values.firstWhere((l) => l.code == code, orElse: () => en);
}

/// The language the interface is currently shown in. Changed from Settings
/// (the app restarts its widget tree afterwards so every screen rebuilds).
class Lang {
  static AppLanguage current = AppLanguage.en;
}

/// Looks up the text shown for [en] in the current language.
///
/// The English wording is the key. Anything without a translation is shown
/// in English, so a missing entry can never break a screen. Use `{name}`
/// placeholders for values: `tr('Only {n} left', {'n': 3})`.
String tr(String en, [Map<String, Object?>? args]) {
  var s = Lang.current == AppLanguage.ta ? (taStrings[en] ?? en) : en;
  if (args != null) {
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  }
  return s;
}
