/// Background work for occasional case-battery refreshes and notifications.

import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rxdart/rxdart.dart';
import 'package:workmanager/workmanager.dart';

import '../../../cubit/headphones_connection_cubit.dart';
import '../../../cubit/headphones_cubit_objects.dart';
import '../../../di.dart' as di;
import '../../../headphones/framework/lrc_battery.dart';
import '../../../logger.dart';
import '../appwidgets/battery_appwidget.dart';

const commonTimeout = Duration(seconds: 10);
const taskIdRoutineUpdate = 'freebuddy.routine_update';
const lowCaseBatteryThreshold = 20;
const notificationChannelId = 'case_battery_low';

final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _notifications.initialize(const InitializationSettings(android: android));
  final androidPlugin = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.requestNotificationsPermission();
  await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
    notificationChannelId,
    'Case battery',
    description: 'Low case battery alerts for FreeBuds',
    importance: Importance.low,
  ));
}

Future<void> _checkLowCaseBattery(LRCBatteryLevels batteryData) async {
  final level = batteryData.levelCase;
  if (level == null || batteryData.chargingCase) return;
  final prefs = await SharedPreferences.getInstance();
  final alreadyNotified = prefs.getBool('case_low_notified') ?? false;
  if (level <= lowCaseBatteryThreshold && !alreadyNotified) {
    await _notifications.show(
      1001,
      'FreeBuds case battery',
      'Case FreeBuds: $level%',
      const NotificationDetails(android: AndroidNotificationDetails(
        notificationChannelId,
        'Case battery',
        channelDescription: 'Low case battery alerts for FreeBuds',
        importance: Importance.low,
        priority: Priority.low,
        icon: '@mipmap/ic_launcher',
        onlyAlertOnce: true,
      )),
    );
    await prefs.setBool('case_low_notified', true);
  } else if (level > lowCaseBatteryThreshold && alreadyNotified) {
    await prefs.setBool('case_low_notified', false);
  }
}

Future<bool> routineUpdateCallback() async {
  HeadphonesConnectionCubit? cubit;
  try {
    if (await HeadphonesConnectionCubit.cubitAlreadyRunningSomewhere()) return true;
    cubit = di.getHeadphonesCubit();
    final headphones = await cubit.stream
        .debounceTime(const Duration(seconds: 1))
        .firstWhere((e) => e is! HeadphonesConnecting)
        .timeout(commonTimeout);
    if (headphones is! HeadphonesConnectedOpen || headphones.headphones is! LRCBattery) return true;
    final batteryData = await (headphones.headphones as LRCBattery).lrcBattery.first.timeout(commonTimeout);
    await updateBatteryHomeWidget(batteryData);
    await _checkLowCaseBattery(batteryData);
    await cubit.close();
    return true;
  } catch (e) {
    await cubit?.close();
    rethrow;
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    DartPluginRegistrant.ensureInitialized();
    await initNotifications();
    try {
      return switch (task) {
        taskIdRoutineUpdate => await routineUpdateCallback().timeout(commonTimeout),
        String() => throw Exception('No such task named $task'),
      };
    } catch (e, s) {
      loggI.e('Periodic task $task failed', error: e, stackTrace: s);
      return false;
    }
  });
}

/// Bluetooth connection broadcasts trigger an immediate refresh; this is only a low-frequency safety net.
Future<void> init() async {
  await initNotifications();
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  await Workmanager().registerPeriodicTask(
    taskIdRoutineUpdate,
    taskIdRoutineUpdate,
    frequency: const Duration(minutes: 30),
    initialDelay: const Duration(minutes: 5),
    existingWorkPolicy: ExistingWorkPolicy.update,
    backoffPolicy: BackoffPolicy.linear,
  );
}
