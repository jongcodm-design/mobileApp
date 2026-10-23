import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../database/database_helper.dart';
import '../models/class_item.dart';

@visibleForTesting
Future<List<ClassItem>> readClassesBeforeClearingReminders({
  required Future<List<ClassItem>> Function() readClasses,
  required Future<void> Function() cancelAll,
}) async {
  final classes = await readClasses();
  await cancelAll();
  return classes;
}

/// Local-only weekly system notifications scheduled before each class.
class ReminderService extends ChangeNotifier {
  ReminderService._();
  static final ReminderService instance = ReminderService._();
  static const _enabledKey = 'class_reminders_enabled';
  // Android keeps a channel's description from its first creation, so the ID
  // is bumped to pick up the corrected description on existing installs.
  static const _channelId = 'class_schedule_reminders_v3';
  static const _channelDescription =
      'Reminders 10 minutes before each class, every week.';
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Upcoming classes',
        description: _channelDescription,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
    // Remove the channel from before the ID bump so it stops appearing in settings.
    await android?.deleteNotificationChannel(channelId: 'class_schedule_reminders_v2');
    _initialized = true;
  }

  Future<bool> get isEnabled async =>
      (await SharedPreferences.getInstance()).getBool(_enabledKey) ?? false;

  Future<bool> enable() async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final androidGranted = await android?.requestNotificationsPermission();
    if (android != null && androidGranted != true) return false;
    if (android != null) await requestExactAlarmsAccess();
    final iosGranted = await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    final granted = android != null || ios != null
        ? android != null || iosGranted == true
        : false;
    if (!granted) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, true);
    notifyListeners();
    await sync();
    return true;
  }

  Future<bool> get exactAlarmsAvailable async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.canScheduleExactNotifications() ?? true;
  }

  Future<bool> requestExactAlarmsAccess() async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return true;
    if (await android.canScheduleExactNotifications() == true) return true;
    await android.requestExactAlarmsPermission();
    final granted = await android.canScheduleExactNotifications() == true;
    if (granted && await isEnabled) await sync();
    return granted;
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    notifyListeners();
    await initialize();
    await _plugin.cancelAll();
  }

  Future<void> sync() async {
    if (!await isEnabled) return;
    await initialize();
    // Keep the current reminders if the local schedule cannot be read.
    final classes = await readClassesBeforeClearingReminders(
      readClasses: DatabaseHelper.instance.getAll,
      cancelAll: _plugin.cancelAll,
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final exactAlarmsAvailable =
        await android?.canScheduleExactNotifications() ?? false;
    final now = tz.TZDateTime.now(tz.local);
    for (final c in classes) {
      final reminderMinutes = c.startMinutes >= 10
          ? c.startMinutes - 10
          : c.startMinutes;
      var next = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        reminderMinutes ~/ 60,
        reminderMinutes % 60,
      );
      while (next.weekday != c.day || !next.isAfter(now)) {
        next = next.add(const Duration(days: 1));
        if (next.weekday == c.day) {
          next = tz.TZDateTime(
            tz.local,
            next.year,
            next.month,
            next.day,
            reminderMinutes ~/ 60,
            reminderMinutes % 60,
          );
        }
      }
      final id = (c.id ?? _stableId(c)) & 0x7fffffff;
      await _plugin.zonedSchedule(
        id: id,
        title: 'Class starting soon',
        body: _reminderBody(c),
        scheduledDate: next,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Upcoming classes',
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: exactAlarmsAvailable
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: 'class:${c.id ?? _stableId(c)}',
      );
    }
  }

  // Reads correctly with or without a room: "Network Lab, room to confirm."
  String _reminderBody(ClassItem c) {
    final room = c.room.trim().toLowerCase();
    final roomKnown =
        room.isNotEmpty && room != 'room to confirm' && room != 'unknown room';
    return roomKnown
        ? '${c.subject} · ${formatRoom(c.room)}. Starts in 10 minutes.'
        : '${c.subject}, room to confirm. Starts in 10 minutes.';
  }

  int _stableId(ClassItem c) =>
      '${c.subject}|${c.room}|${c.day}|${c.startMinutes}'.hashCode;
}
