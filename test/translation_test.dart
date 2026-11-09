import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/constants.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:gellsoft_rentpro/l10n/ta.dart';
import 'package:gellsoft_rentpro/subscription/plan.dart';

/// Shown the same in every language on purpose.
const keepEnglish = <String>{'WhatsApp', 'PIN'};

String unescape(String s) => s
    .replaceAll(r'\n', '\n')
    .replaceAll(r"\'", "'")
    .replaceAll(r'\"', '"')
    .replaceAll(r'\$', r'$')
    .replaceAll(r'\\', r'\');

/// Every phrase the code passes to tr(), plus those that reach it through
/// a variable (enum names and the categories of each shop type).
Set<String> phrasesInCode() {
  final re = RegExp(
    r"""\btr\(\s*(?:'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)")""",
  );
  final out = <String>{};
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    if (f.path.replaceAll('\\', '/').contains('lib/l10n/')) continue;
    for (final m in re.allMatches(f.readAsStringSync())) {
      out.add(unescape(m.group(1) ?? m.group(2)!));
    }
  }
  out
    ..addAll(ShopType.values.map((t) => t.en))
    ..addAll(ShopType.values.expand((t) => t.categories))
    ..addAll(ProFeature.values.map((f) => f.en))
    ..addAll(RateType.values.map((r) => r.en))
    ..addAll(ItemStatus.values.map((s) => s.en));
  return out;
}

Set<String> placeholders(String s) =>
    RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toSet();

void main() {
  tearDown(() => Lang.current = AppLanguage.en);

  test('every phrase in the code has a Tamil translation', () {
    final missing =
        phrasesInCode()
            .where((p) => !taStrings.containsKey(p) && !keepEnglish.contains(p))
            .toList()
          ..sort();
    expect(
      missing,
      isEmpty,
      reason: 'Add these to lib/l10n/ta.dart:\n${missing.join('\n')}',
    );
  });

  test('no Tamil entry is unused (catches typos in keys)', () {
    final used = phrasesInCode();
    final unused = taStrings.keys.where((k) => !used.contains(k)).toList()
      ..sort();
    expect(
      unused,
      isEmpty,
      reason: 'Not used by any tr():\n${unused.join('\n')}',
    );
  });

  test('translations keep the same {placeholders} as the English', () {
    final bad = [
      for (final e in taStrings.entries)
        if (placeholders(e.key).difference(placeholders(e.value)).isNotEmpty ||
            placeholders(e.value).difference(placeholders(e.key)).isNotEmpty)
          e.key,
    ];
    expect(bad, isEmpty, reason: 'Placeholder mismatch:\n${bad.join('\n')}');
  });

  test('every translation really contains Tamil letters', () {
    final tamil = RegExp(r'[஀-௿]');
    final bad = [
      for (final e in taStrings.entries)
        if (!tamil.hasMatch(e.value)) e.key,
    ];
    expect(bad, isEmpty, reason: 'No Tamil in:\n${bad.join('\n')}');
  });

  test('no key is written twice in ta.dart', () {
    final src = File('lib/l10n/ta.dart').readAsStringSync();
    final keys = RegExp(
      r"""^\s*'((?:[^'\\\n]|\\.)*)':""",
      multiLine: true,
    ).allMatches(src).map((m) => m.group(1)!).toList();
    final seen = <String>{};
    final dup = keys.where((k) => !seen.add(k)).toList();
    expect(dup, isEmpty, reason: 'Duplicate keys:\n${dup.join('\n')}');
  });

  test('tr() uses English by default, Tamil when switched, fills {x}', () {
    expect(tr('Bookings'), 'Bookings');
    Lang.current = AppLanguage.ta;
    expect(tr('Bookings'), 'முன்பதிவுகள்');
    expect(tr('Welcome to {app}', {'app': 'X'}), 'X-க்கு வரவேற்கிறோம்');
    expect(tr('Some brand new text'), 'Some brand new text');
  });
}
