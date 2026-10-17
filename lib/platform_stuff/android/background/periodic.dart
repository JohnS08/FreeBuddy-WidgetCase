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
/// When the activity is paused, a background isolate cannot read fresh values
/// from the UI cubit, so it replaces that cubit deliberately. [force] is kept
/// for explicit callers that need the same takeover regardless of lifecycle.
Future<bool> routineUpdateCallback({bool force = false}) async {
  if (_pollInProgress) return true;
  _pollInProgress = true;
  HeadphonesConnectionCubit? cubit;
  try {
    final prefs = await SharedPreferences.getInstance();
    final uiIsActive = prefs.getBool(appInForegroundKey) ?? true;
    final cubitIsAlive =
        await HeadphonesConnectionCubit.cubitAlreadyRunningSomewhere();
    if (!force && cubitIsAlive && uiIsActive) {
      // The UI isolate must not post notifications itself: the native call can
      // briefly block the Flutter frame. Use the one-off background task and
      // the latest value saved by the UI listener instead.
      await checkStoredCaseBatteryNotification();
      return true;
    }
    if ((force || !uiIsActive) && cubitIsAlive) {
      await HeadphonesConnectionCubit.killOtherCubit();
    }
    cubit = di.getHeadphonesCubit();
    var headphones = await cubit.stream
        .debounceTime(const Duration(seconds: 1))
        .firstWhere((e) => e is! HeadphonesConnecting)
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
      await checkStoredCaseBatteryNotification();
      await cubit.close();
      return true;
    }
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
  } finally {
    _pollInProgress = false;
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
    // A killed or unavailable Bluetooth session must not suppress the alert.
    // Use the last value saved by the widget as a fallback for this poll.
    try {
      await checkStoredCaseBatteryNotification();
    } catch (fallbackError, fallbackStack) {
      loggI.e('Stored battery fallback failed',
          error: fallbackError, stackTrace: fallbackStack);
    }
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
