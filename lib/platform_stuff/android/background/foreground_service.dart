import 'dart:async';
import 'dart:ui';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../logger.dart';
import 'periodic.dart' as periodic;

const _serviceId = 43929;

@pragma('vm:entry-point')
void foregroundTaskCallback() {
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(_FreeBuddyTaskHandler());
}

class _FreeBuddyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await periodic.initNotifications();
    await _poll();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_poll());
  }

  Future<void> _poll() async {
    try {
      await periodic.routineUpdateCallback()
          .timeout(periodic.commonTimeout);
    } catch (error, stackTrace) {
      loggI.w('Foreground battery poll failed',
          error: error, stackTrace: stackTrace);
      try {
        await periodic.checkStoredCaseBatteryNotification();
      } catch (fallbackError, fallbackStack) {
        loggI.w('Foreground stored-value fallback failed',
            error: fallbackError, stackTrace: fallbackStack);
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {}
}

Future<void> initForegroundService() async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'freebuddy_foreground_service',
      channelName: 'FreeBuddy работает в фоне',
      channelDescription:
          'Нужно для мониторинга Bluetooth и уведомлений о заряде кейса',
      onlyAlertOnce: true,
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      showWhen: false,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(60000),
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );

  if (await FlutterForegroundTask.isRunningService) return;

  await FlutterForegroundTask.startService(
    serviceId: _serviceId,
    serviceTypes: [ForegroundServiceTypes.connectedDevice],
    notificationTitle: 'FreeBuddy работает в фоне',
    notificationText: 'Мониторинг заряда кейса включён',
    callback: foregroundTaskCallback,
  );
}

/// Called from an explicit settings action, not during application startup.
Future<void> requestBackgroundPermissions() async {
  final notificationPermission =
      await FlutterForegroundTask.checkNotificationPermission();
  if (notificationPermission != NotificationPermission.granted) {
    await FlutterForegroundTask.requestNotificationPermission();
  }

  if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }
}
