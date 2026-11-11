# GellSoft RentPro: how it is built

Flutter (Android only), Riverpod, SQLite (sqflite). The look and the subscription code are shared in spirit with GellSoft BillPro: the same design language (Aurora theme, floating bar, soft cards) in midnight navy and gold, and the same license client, with RentPro's own server copy.

## Folders
- `lib/core`: theme, formats, GST and booking maths (`booking_math.dart`, `gst.dart`), sharing and WhatsApp links (`share.dart`), PDF fonts.
- `lib/data`: the database (`database.dart`, schema version 1), repositories (`repositories.dart` items and customers, `booking_repo.dart`, `invoice_repo.dart`, `report_repo.dart`), exports (`csv_export.dart`), reminders (`reminders.dart`), notifications (`notifications.dart`), backup (`backup_service.dart`, `cloud_backup.dart`), shop profile and settings.
- `lib/features`: one folder per area (home, bookings, items, customers, invoices, reminders, reports, settings, onboarding, splash).
- `lib/subscription`: plan rules (`plan.dart`), license (`license_*.dart`), Google Play purchase, account, clock check, Pro screen.
- `lib/l10n`: `tr('English')` and the Tamil table `ta.dart`; `test/translation_test.dart` makes sure every phrase has Tamil.

## Rules that live in one place
- Free limits: `FreePlan` in `plan.dart` (12 bookings a month, 2 photos a booking). They are enforced in `BookingRepo` (the data layer), not only in screens.
- A booking blocks an item from pickup to return, both days included; cancelled and returned bookings do not block; an item still out and late stays blocked until it is back.
- Money: `splitMoney` shares the discount between lines by amount and taxes each line at its own rate (added on top, or taken out when rents include GST). A booking stores `rent_total`, `tax_total` and `payable`; deposit is separate and never taxed.
- Invoices keep their own copy of the customer and every line, so they never change; numbers are never reused.
- `buildReminders` (pure) drives the Reminders page, the Home badge and the notifications.

## Notifications
`planNotifications` (pure) works out the next 14 days; `NotificationService.sync` clears and sets them again each time the app opens or something changes. They are Pro only and use inexact alarms (no special permission).

## The license server
RentPro talks to its own copy of the license server at `https://playstore.gellsoft.com/rentpro` (code in `playlicense-server`, setup in `deploy/rentpro`). Product id `gellsoft_pro`, package `com.gellsoft.gellsoft_rentpro`.

## Tests
`flutter test`: data layer (bookings, availability, GST, invoices, reports, CSV, backup), widget flows on a temporary database (invoices, photos, reminders, reports, settings), licensing and purchase flows ported from BillPro, translations. Widget tests that use the real database seed and close it inside `tester.runAsync` (see `testDb`).
