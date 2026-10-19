import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

const nativeMonitorChannel = MethodChannel(
  'com.lastgimbus.the.freebuddy/native_monitor',
);

Future<void> initForegroundService() async {
  await nativeMonitorChannel.invokeMethod<void>('start');
}

/// Requests only permissions that must be initiated from the visible Activity.
Future<void> requestBackgroundPermissions() async {
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }
  await nativeMonitorChannel.invokeMethod<void>('requestBackgroundPermissions');
}
