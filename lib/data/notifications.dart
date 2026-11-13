import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/format.dart';
import '../l10n/strings.dart';
import '../subscription/entitlement.dart';
import 'booking_models.dart';
import 'booking_repo.dart';
import 'business_profile.dart';
import 'reminders.dart';
import 'shops.dart';

/// What the shop owner chose for reminder notifications (a Pro feature).
class NotifySettings {
  const NotifySettings({
    this.daily = true,
    this.beforeEvent = true,
    this.hour = 8,
    this.minute = 0,
    this.extraTimes = const [],
  });

  /// The most reminder times a day.
  static const maxTimes = 4;

  /// A summary each morning of what needs doing that day.
  final bool daily;

  /// A reminder for each booking, [Booking.remindDays] before its event, and
  /// another on the day the items are due back.
  final bool beforeEvent;
  final int hour;
  final int minute;

  /// More times of day for the same reminders, as minutes after midnight, so
  /// the shop can be told more than once a day.
  final List<int> extraTimes;

  TimeOfDay get time => TimeOfDay(hour: hour, minute: minute);

  /// Every reminder time, as minutes after midnight, earliest first, with no
  /// time twice and at most [maxTimes].
  List<int> get times {
    final all = <int>{hour * 60 + minute, ...extraTimes}.toList()..sort();
    return all.length > maxTimes ? all.sublist(0, maxTimes) : all;
  }

  List<TimeOfDay> get timesOfDay => [
    for (final m in times) TimeOfDay(hour: m ~/ 60, minute: m % 60),
  ];

  /// The same settings with [minutes] (minutes after midnight) as the times.
  NotifySettings withTimes(List<int> minutes) {
    final all = <int>{...minutes}.toList()..sort();
    if (all.isEmpty) return this;
    final kept = all.length > maxTimes ? all.sublist(0, maxTimes) : all;
    return NotifySettings(
      daily: daily,
      beforeEvent: beforeEvent,
      hour: kept.first ~/ 60,
      minute: kept.first % 60,
      extraTimes: kept.sublist(1),
    );
  }

  NotifySettings copyWith({
    bool? daily,
    bool? beforeEvent,
    int? hour,
    int? minute,
    List<int>? extraTimes,
  }) => NotifySettings(
    daily: daily ?? this.daily,
    beforeEvent: beforeEvent ?? this.beforeEvent,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    extraTimes: extraTimes ?? this.extraTimes,
  );

  static Future<NotifySettings> load() async {
    final sp = await SharedPreferences.getInstance();
    return NotifySettings(
      daily: sp.getBool('n_daily') ?? true,
      beforeEvent: sp.getBool('n_before') ?? true,
      hour: sp.getInt('n_hour') ?? 8,
      minute: sp.getInt('n_minute') ?? 0,
      extraTimes: [
        for (final s in sp.getStringList('n_extra') ?? const <String>[])
          if (int.tryParse(s) case final m? when m >= 0 && m < 1440) m,
      ],
    );
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('n_daily', daily);
    await sp.setBool('n_before', beforeEvent);
    await sp.setInt('n_hour', hour);
    await sp.setInt('n_minute', minute);
    await sp.setStringList('n_extra', [for (final m in extraTimes) '$m']);
  }
}

class NotifySettingsNotifier extends AsyncNotifier<NotifySettings> {
  @override
  Future<NotifySettings> build() => NotifySettings.load();

  Future<void> setSettings(NotifySettings s) async {
    await s.save();
    state = AsyncData(s);
  }
}

final notifySettingsProvider =
    AsyncNotifierProvider<NotifySettingsNotifier, NotifySettings>(
      NotifySettingsNotifier.new,
    );

/// One reminder to be shown at a set time.
class PlannedNotification {
  const PlannedNotification(this.id, this.at, this.title, this.body);
  final int id;
  final DateTime at;
  final String title;
  final String body;
}

/// How many days ahead notifications are planned. The plan is made again each
/// time the app opens, so this only matters if the app is left closed.
const notifyDaysAhead = 14;

/// The most notifications set at once (Android handles a few hundred, but a
/// phone full of alarms helps nobody).
const notifyLimit = 60;

/// Works out which notifications should be waiting on the phone: a morning
/// summary for each of the next days and a reminder for each booking.
///
/// This is a pure function of the bookings, the settings and the time, so it
/// can be checked without a phone.
///
/// [idOffset] keeps the ids of one shop apart from another's, [label] is put
/// before each title when there is more than one shop, and [service] words
/// the reminders for appointments instead of items going out and back.
List<PlannedNotification> planNotifications({
  required List<Booking> bookings,
  required NotifySettings settings,
  required DateTime now,
  int days = notifyDaysAhead,
  int idOffset = 0,
  String label = '',
  bool service = false,
}) {
  String titled(String t) => label.isEmpty ? t : '$label: $t';
  final out = <PlannedNotification>[];
  final today = dayOf(now);
  final times = settings.times;
  DateTime at(DateTime d, int minutes) =>
      DateTime(d.year, d.month, d.day, minutes ~/ 60, minutes % 60);

  if (settings.daily) {
    for (var i = 0; i < days; i++) {
      final date = DateTime(today.year, today.month, today.day + i);
      final items = buildReminders(bookings, date);
      if (items.isEmpty) continue;
      int n(ReminderKind k) => items.where((r) => r.kind == k).length;
      final parts = <String>[
        if (n(ReminderKind.overdue) > 0)
          tr('{n} overdue', {'n': n(ReminderKind.overdue)}),
        if (n(ReminderKind.returnDue) > 0)
          tr('{n} due back', {'n': n(ReminderKind.returnDue)}),
        if (n(ReminderKind.sendItems) > 0)
          tr('{n} to send', {'n': n(ReminderKind.sendItems)}),
        if (n(ReminderKind.balance) > 0)
          tr('{n} with money due', {'n': n(ReminderKind.balance)}),
      ];
      for (var t = 0; t < times.length; t++) {
        final when = at(date, times[t]);
        if (!when.isAfter(now)) continue;
        out.add(
          PlannedNotification(
            idOffset + 1000 + i * 10 + t,
            when,
            titled(tr('{n} things need you today', {'n': items.length})),
            parts.join(', '),
          ),
        );
      }
    }
  }

  if (settings.beforeEvent) {
    for (final b in bookings) {
      final names = b.lines.map((l) => l.label).join(', ');
      if (b.status == BookingStatus.booked) {
        final remindDay = b.eventDate.subtract(Duration(days: b.remindDays));
        for (var t = 0; t < times.length; t++) {
          final when = at(remindDay, times[t]);
          if (!when.isAfter(now) ||
              dayOf(when).isAfter(today.add(Duration(days: days)))) {
            continue;
          }
          out.add(
            PlannedNotification(
              idOffset + 100000 + b.id * 20 + t,
              when,
              titled(
                service
                    ? tr('Appointment coming up: #{n}', {'n': b.number})
                    : tr('Send the items for #{n}', {'n': b.number}),
              ),
              service
                  ? tr('{items} for {name} on {date}{time}', {
                      'items': names,
                      'name': b.customerName,
                      'date': dateText(b.eventDate),
                      'time': b.eventTime.isEmpty
                          ? ''
                          : ' ${tr('at')} ${timeText(b.eventTime)}',
                    })
                  : tr('{items} for {name}, event on {date}', {
                      'items': names,
                      'name': b.customerName,
                      'date': dateText(b.eventDate),
                    }),
            ),
          );
        }
      }
      if (!service &&
          (b.status == BookingStatus.booked ||
              b.status == BookingStatus.pickedUp)) {
        for (var t = 0; t < times.length; t++) {
          final when = at(b.returnDate, times[t]);
          if (!when.isAfter(now) ||
              dayOf(when).isAfter(today.add(Duration(days: days)))) {
            continue;
          }
          out.add(
            PlannedNotification(
              idOffset + 100000 + b.id * 20 + 10 + t,
              when,
              titled(tr('Items due back today: #{n}', {'n': b.number})),
              tr('{items} from {name}', {
                'items': names,
                'name': b.customerName,
              }),
            ),
          );
        }
      }
    }
  }

  out.sort((a, b) => a.at.compareTo(b.at));
  return out.length > notifyLimit ? out.sublist(0, notifyLimit) : out;
}

/// What the phone has to do. Tests replace it with a recording copy.
abstract class NotificationBackend {
  Future<void> init();

  /// Asks the user for permission to show notifications. True when allowed.
  Future<bool> requestPermission();
  Future<void> cancelAll();
  Future<void> schedule(PlannedNotification n);
}

class _LocalBackend implements NotificationBackend {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Items to send out and bring back, and money to collect',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  @override
  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    // the shop is in India, so reminders follow Indian time
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  @override
  Future<void> schedule(PlannedNotification n) async {
    await init();
    await _plugin.zonedSchedule(
      id: n.id,
      title: n.title,
      body: n.body,
      scheduledDate: tz.TZDateTime.from(n.at, tz.local),
      notificationDetails: _details,
      // "inexact": the phone may shift it by a few minutes to save battery, and
      // no special permission is needed
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}

/// The open bookings of another shop on the phone, for reminders.
class ShopReminders {
  const ShopReminders({
    required this.name,
    required this.service,
    required this.bookings,
  });
  final String name;
  final bool service;
  final List<Booking> bookings;
}

class NotificationService {
  @visibleForTesting
  static NotificationBackend backend = _LocalBackend();

  /// Makes the phone's waiting notifications match the bookings of every
  /// shop. Without Pro (or with both switches off) nothing is left scheduled.
  /// With more than one shop each title says which shop it is for.
  static Future<int> sync({
    required bool isPro,
    required NotifySettings settings,
    required List<Booking> bookings,
    DateTime? now,
    bool service = false,
    String shopName = '',
    List<ShopReminders> others = const [],
  }) async {
    await backend.cancelAll();
    if (!isPro || (!settings.daily && !settings.beforeEvent)) return 0;
    final at = now ?? DateTime.now();
    final many = others.isNotEmpty;
    final all = <PlannedNotification>[
      ...planNotifications(
        bookings: bookings,
        settings: settings,
        now: at,
        label: many ? shopName : '',
        service: service,
      ),
      for (final (i, o) in others.indexed)
        ...planNotifications(
          bookings: o.bookings,
          settings: settings,
          now: at,
          idOffset: (i + 1) * 10000000,
          label: o.name,
          service: o.service,
        ),
    ]..sort((a, b) => a.at.compareTo(b.at));
    final plan = all.length > notifyLimit ? all.sublist(0, notifyLimit) : all;
    for (final n in plan) {
      await backend.schedule(n);
    }
    return plan.length;
  }

  /// Ask for permission (Android 13 and later show a prompt).
  static Future<bool> askPermission() => backend.requestPermission();
}

/// The first time the app opens, asks to show notifications (Android 13 and
/// later show a prompt). It asks only once: a person who said no is not asked
/// again at every start, and can turn it on in the phone's settings.
Future<void> askNotificationPermissionOnFirstOpen() async {
  try {
    final sp = await SharedPreferences.getInstance();
    if (sp.getBool('s_notifask') ?? false) return;
    // marked first, so a prompt that is closed, or a crash, never repeats it
    await sp.setBool('s_notifask', true);
    await NotificationService.askPermission();
  } catch (_) {
    // the app works without notifications; never get in its way
  }
}

/// Brings the phone's reminders up to date: call it when the app opens and
/// whenever a booking or a setting changes.
Future<void> syncNotifications(WidgetRef ref) async {
  try {
    final settings =
        ref.read(notifySettingsProvider).valueOrNull ?? await NotifySettings.load();
    final repo = ref.read(bookingRepoProvider);
    final bookings = await repo.forReminders();
    final mine = ref.read(profileProvider).valueOrNull;
    // the other shops on the phone get their reminders too
    final others = <ShopReminders>[];
    for (final id in Shops.all) {
      if (id == Shops.activeId) continue;
      try {
        final p = await BusinessProfile.load(shop: id);
        if (p == null) continue;
        others.add(
          ShopReminders(
            name: p.name,
            service: p.type.isService,
            bookings: await repo.forRemindersOf(id),
          ),
        );
      } catch (_) {
        // a shop that cannot be read is left out; the others still get theirs
      }
    }
    await NotificationService.sync(
      isPro: ref.read(isProProvider),
      settings: settings,
      bookings: bookings,
      service: mine?.type.isService ?? false,
      shopName: mine?.name ?? '',
      others: others,
    );
  } catch (_) {
    // a notification that cannot be set must never get in the way of the app
  }
}
