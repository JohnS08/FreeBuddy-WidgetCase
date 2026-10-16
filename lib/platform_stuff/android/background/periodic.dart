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
const defaultCaseBatteryThreshold = 20;
const caseBatteryThresholdPreferenceKey = 'caseBatteryThreshold';
const lastCaseLevelKey = 'case_last_level';
const lastCaseChargingKey = 'case_last_charging';
const notificationChannelId = 'case_battery_low_v3';

final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _notifications.initialize(const InitializationSettings(android: android));
  final androidPlugin = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.requestNotificationsPermission();
  await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
    notificationChannelId,
    'Заряд кейса',
    description: 'Уведомления о низком заряде кейса FreeBuds',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  ));
}

Future<void> _checkLowCaseBattery({
  required int? level,
  required bool charging,
}) async {
  if (level == null || charging) return;
  final prefs = await SharedPreferences.getInstance();
  final threshold = prefs.getInt(caseBatteryThresholdPreferenceKey) ??
      defaultCaseBatteryThreshold;
  if (level <= threshold) {
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
      'Низкий заряд кейса FreeBuds',
      'Case FreeBuds: $level%',
      const NotificationDetails(android: AndroidNotificationDetails(
        notificationChannelId,
        'Заряд кейса',
        channelDescription: 'Уведомления о низком заряде кейса FreeBuds',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: true,
        enableVibration: true,
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
      )),
    );
  }
}

/// Re-check the latest value immediately after the threshold changes.
Future<void> checkStoredCaseBatteryNotification() async {
  final prefs = await SharedPreferences.getInstance();
  final storedLevel = prefs.getInt(lastCaseLevelKey);
  if (storedLevel == null || storedLevel < 0) return;
  await initNotifications();
  await _checkLowCaseBattery(
    level: storedLevel,
    charging: prefs.getBool(lastCaseChargingKey) ?? false,
  );
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
    await _checkLowCaseBattery(
      level: batteryData.levelCase,
      charging: batteryData.chargingCase,
    );
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
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    backoffPolicy: BackoffPolicy.linear,
  );
}
