/// Session reminders.
///
/// The app's value depends on the user actually coming back: a personal baseline
/// needs eight sessions before it says anything, and a trend needs them to keep
/// coming. A reminder every couple of days is the whole retention mechanism, and it
/// is deliberately the only notification the app ever sends.
///
/// Nothing here mentions a result. A push notification is read on a lock screen,
/// possibly by someone other than the user, so it says "time for a session" and
/// never anything about what the last one found.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Identifier of the recurring reminder, so rescheduling replaces it rather than
/// adding a second one.
const int kReminderNotificationId = 1001;

/// Android channel for reminders.
const String kReminderChannelId = 'neurascan_reminders';

/// Hour of the day reminders fire.
///
/// Late morning: reaction time and recall both vary through the day, and a baseline
/// built from sessions at scattered hours has that variation folded into it as if it
/// were the user's own noise. A consistent time makes the baseline tighter and so
/// makes a real change easier to see.
const int kReminderHour = 10;

/// What the app needs from the notification plugin.
///
/// An interface so that widget tests can assert a reminder was scheduled without a
/// platform channel. The scheduling logic is worth testing; the plugin is not.
abstract interface class ReminderScheduler {
  Future<void> initialise();

  /// Requests permission, returning whether it was granted.
  ///
  /// A refusal is not an error. The app works without reminders; it just works
  /// less well, and nagging about it would be worse than the lost sessions.
  Future<bool> requestPermission();

  /// Schedules a reminder every [intervalDays] days, replacing any existing one.
  Future<void> scheduleReminder({
    required int intervalDays,
    required String title,
    required String body,
  });

  Future<void> cancelReminder();

  /// Whether a reminder is currently scheduled.
  Future<bool> hasPendingReminder();
}

/// Reminders through `flutter_local_notifications`.
class NotificationService implements ReminderScheduler {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialised = false;

  @override
  Future<void> initialise() async {
    if (_initialised) return;

    // The time zone database has to be loaded before a zoned schedule can be
    // built. Without it a reminder set for 10 am would fire at 10 am UTC.
    tz_data.initializeTimeZones();

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Permission is requested later, from the settings screen, rather than
          // on first launch. A permission prompt before the user knows what the
          // app is gets refused, and on iOS that refusal is close to permanent.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialised = true;
  }

  @override
  Future<bool> requestPermission() async {
    await initialise();

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }

    return false;
  }

  @override
  Future<void> scheduleReminder({
    required int intervalDays,
    required String title,
    required String body,
  }) async {
    await initialise();
    await cancelReminder();

    await _plugin.zonedSchedule(
      id: kReminderNotificationId,
      title: title,
      body: body,
      scheduledDate: _nextReminderTime(intervalDays),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          kReminderChannelId,
          'Session reminders',
          channelDescription: 'Reminds you when a screening session is due. Never mentions results.',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // Repeats at the same clock time each cycle. Inexact scheduling is
      // deliberate: an exact alarm needs a special permission on Android 12 and
      // later, and a reminder that arrives half an hour late is no worse.
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> cancelReminder() async {
    await initialise();
    await _plugin.cancel(id: kReminderNotificationId);
  }

  @override
  Future<bool> hasPendingReminder() async {
    await initialise();
    final pending = await _plugin.pendingNotificationRequests();
    return pending.any((request) => request.id == kReminderNotificationId);
  }

  /// The next reminder time: [intervalDays] from now, at [kReminderHour].
  tz.TZDateTime _nextReminderTime(int intervalDays) {
    final now = tz.TZDateTime.now(tz.local);
    var target = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      kReminderHour,
    ).add(Duration(days: intervalDays));

    // If the arithmetic lands in the past -- which it can across a daylight-saving
    // change -- push it on by a day rather than scheduling something that fires
    // immediately.
    while (target.isBefore(now)) {
      target = target.add(const Duration(days: 1));
    }
    return target;
  }
}

/// A scheduler that records calls instead of making them, for tests.
class FakeReminderScheduler implements ReminderScheduler {
  FakeReminderScheduler({this.permissionGranted = true});

  bool permissionGranted;
  bool initialised = false;
  int permissionRequests = 0;
  int cancellations = 0;

  /// Every reminder scheduled, in order.
  final scheduled = <({int intervalDays, String title, String body})>[];

  @override
  Future<void> initialise() async => initialised = true;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permissionGranted;
  }

  @override
  Future<void> scheduleReminder({
    required int intervalDays,
    required String title,
    required String body,
  }) async {
    scheduled.add((intervalDays: intervalDays, title: title, body: body));
  }

  @override
  Future<void> cancelReminder() async {
    cancellations++;
    scheduled.clear();
  }

  @override
  Future<bool> hasPendingReminder() async => scheduled.isNotEmpty;
}
