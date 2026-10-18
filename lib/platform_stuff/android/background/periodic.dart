/// Background work for occasional case-battery refreshes and notifications.

import 'dart:async';
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
const lastCaseUpdatedAtKey = 'case_last_updated_at';
const appInForegroundKey = 'app_in_foreground';
const notificationChannelId = 'case_battery_low_v3';

final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
Future<void>? _notificationsInit;

Future<void> initNotifications() {
  return _notificationsInit ??= _initNotifications();
}

Future<void> _initNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _notifications.initialize(const InitializationSettings(android: android));
  final androidPlugin = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
    notificationChannelId,
    'Заряд кейса',
    description: 'Уведомления о низком заряде кейса FreeBuds',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  ));
}

/// Android permission dialogs must only be requested from the foreground UI.
/// Background isolates call [initNotifications] but never this function.
Future<void> requestNotificationPermissionFromUi() async {
  await initNotifications();
  final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.requestNotificationsPermission();
}

Future<void> setAppInForeground(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(appInForegroundKey, value);
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
  final updatedAt = prefs.getInt(lastCaseUpdatedAtKey);
  if (updatedAt == null ||
      DateTime.now().millisecondsSinceEpoch - updatedAt >
          const Duration(minutes: 10).inMilliseconds) {
    return;
  }
  final storedLevel = prefs.getInt(lastCaseLevelKey);
  if (storedLevel == null || storedLevel < 0) return;
  await initNotifications();
  await _checkLowCaseBattery(
    level: storedLevel,
    charging: prefs.getBool(lastCaseChargingKey) ?? false,
  );
}

bool _pollInProgress = false;

/// Performs one real Bluetooth poll and persists the case level.
///
/// The UI cubit remains the owner while the app process is alive. A background
/// cubit is created only after the UI cubit has disappeared, for example after
/// the system recreates the foreground service process.
Future<bool> routineUpdateCallback() async {
  if (_pollInProgress) return true;
  _pollInProgress = true;
  HeadphonesConnectionCubit? cubit;
  try {
    final cubitIsAlive =
        await HeadphonesConnectionCubit.cubitAlreadyRunningSomewhere();
    if (cubitIsAlive) {
      // The UI cubit continues receiving Bluetooth events while the activity
      // is paused. Never kill it from a foreground-task isolate: doing so
      // leaves the activity with a closed cubit and causes hangs on resume.
      return true;
    }
    cubit = di.getHeadphonesCubit();
    var headphones = await cubit.stream
        .debounceTime(const Duration(seconds: 1))
        .firstWhere((e) => e is HeadphonesConnectedClosed ||
            e is HeadphonesConnectedOpen ||
            e is HeadphonesBluetoothDisabled ||
            e is HeadphonesNoPermission)
        .timeout(commonTimeout);
    if (headphones is HeadphonesConnectedClosed) {
      // connect() waits for the RFCOMM stream to close, so start it without
      // awaiting the whole lifetime of the connection. The background poll
      // only needs the ConnectedOpen transition and the first battery reply.
      final openState = cubit.stream
          .firstWhere((e) => e is HeadphonesConnectedOpen)
          .timeout(commonTimeout);
      unawaited(cubit.connect());
      headphones = await openState;
    }
    if (headphones is! HeadphonesConnectedOpen || headphones.headphones is! LRCBattery) {
      await _closeCubit(cubit);
      return true;
    }
    final batteryData = await (headphones.headphones as LRCBattery).lrcBattery.first.timeout(commonTimeout);
    await updateBatteryHomeWidget(batteryData);
    await _checkLowCaseBattery(
      level: batteryData.levelCase,
      charging: batteryData.chargingCase,
    );
    await _closeCubit(cubit);
    return true;
  } catch (e) {
    await _closeCubit(cubit);
    rethrow;
  } finally {
    _pollInProgress = false;
  }
}

Future<void> _closeCubit(HeadphonesConnectionCubit? cubit) async {
  if (cubit == null) return;
  try {
    await cubit.close().timeout(const Duration(seconds: 2));
  } catch (error, stackTrace) {
    loggI.w('Timed out while closing Bluetooth cubit',
        error: error, stackTrace: stackTrace);
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    DartPluginRegistrant.ensureInitialized();
    await initNotifications();
    try {
      return switch (task) {
        taskIdRoutineUpdate =>
            await routineUpdateCallback().timeout(commonTimeout),
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
