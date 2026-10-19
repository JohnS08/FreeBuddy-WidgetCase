/// Small compatibility layer for Flutter UI lifecycle state.
/// All Bluetooth polling, widget updates and notifications are native now.

import 'package:shared_preferences/shared_preferences.dart';

import 'foreground_service.dart';

const caseBatteryThresholdPreferenceKey = 'caseBatteryThreshold';
const lastCaseLevelKey = 'case_last_level';
const lastCaseChargingKey = 'case_last_charging';
const lastCaseUpdatedAtKey = 'case_last_updated_at';
const appInForegroundKey = 'app_in_foreground';

Future<void> setAppInForeground(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(appInForegroundKey, value);
}

/// Kept for settings compatibility. The native service owns the notification.
Future<void> checkStoredCaseBatteryNotification() async {
  await nativeMonitorChannel.invokeMethod<void>('start');
}

Future<void> init() async {}
