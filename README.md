# GellSoft RentPro

Bookings and rent management for rental shops (wedding costumes, equipment, party decor, vehicles). Flutter, Android only. Sister app of GellSoft BillPro.

- Package: `com.gellsoft.gellsoft_rentpro`
- Theme: Royal Plum (BillPro is teal)
- Free plan: 12 new bookings a month, 2 photos per booking. Pro: unlimited bookings and photos, daily and custom reminder notifications. Limits live in `lib/subscription/plan.dart`.
- Release signing: `android/key.properties` (git-ignored) points at the upload key in `Documents\GellSoft-Keys`.
- Build: `flutter build appbundle --release --obfuscate --split-debug-info=<folder>`; bump the number after `+` in `pubspec.yaml` for every upload.
- Text: write `tr('English')` and add the Tamil in `lib/l10n/ta.dart`; `test/translation_test.dart` checks it.
