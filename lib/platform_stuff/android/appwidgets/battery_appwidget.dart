import 'dart:async';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../cubit/headphones_cubit_objects.dart';
import '../../../headphones/framework/lrc_battery.dart';
import '../../../logger.dart';
import '../background/periodic.dart' as android_periodic;
import '../background/foreground_service.dart' as native_service;

// no better idea for this yet - that's fine
StreamSubscription<LRCBatteryLevels>? _headphonesBatteryStreamSub;
bool _connectionNotificationScheduled = false;

void batteryHomeWidgetHearBloc(BuildContext context,
    HeadphonesConnectionState headphonesConnectionState) async {
  if (headphonesConnectionState is! HeadphonesConnectedOpen) {
    await _headphonesBatteryStreamSub?.cancel();
    _headphonesBatteryStreamSub = null;
    _connectionNotificationScheduled = false;
  } else if (headphonesConnectionState.headphones is LRCBattery) {
    _headphonesBatteryStreamSub =
        (headphonesConnectionState.headphones as LRCBattery)
            .lrcBattery
            .distinct()
            .throttleTime(const Duration(seconds: 1),
                trailing: true, leading: false)
            .listen((event) async {
      logg.d("Updating widget from UI listener: $event");
      await updateBatteryHomeWidget(event);
      if (!_connectionNotificationScheduled) {
        _connectionNotificationScheduled = true;
        unawaited(Future<void>.delayed(
          const Duration(milliseconds: 500),
          android_periodic.checkStoredCaseBatteryNotification,
        ));
      }
    });
  }
}

// this is separate so we can use it from f.e. background stuff
Future<void> updateBatteryHomeWidget(LRCBatteryLevels batteryData) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('case_last_level', batteryData.levelCase ?? -1);
  await prefs.setBool('case_last_charging', batteryData.chargingCase);
  await prefs.setInt(android_periodic.lastCaseUpdatedAtKey,
      DateTime.now().millisecondsSinceEpoch);
  await native_service.nativeMonitorChannel.invokeMethod<void>('updateState', {
    'left': batteryData.levelLeft ?? -1,
    'right': batteryData.levelRight ?? -1,
    'case': batteryData.levelCase ?? -1,
    'leftCharging': batteryData.chargingLeft,
    'rightCharging': batteryData.chargingRight,
    'caseCharging': batteryData.chargingCase,
  });
  await HomeWidget.saveWidgetData<int?>('left', batteryData.levelLeft);
  await HomeWidget.saveWidgetData<int?>('right', batteryData.levelRight);
  await HomeWidget.saveWidgetData<int?>('case', batteryData.levelCase);
  await HomeWidget.saveWidgetData<bool>('case_charging', batteryData.chargingCase);
  await HomeWidget.updateWidget(
    name: 'BatteryWidgetReceiver',
    androidName: 'BatteryWidgetReceiver',
    qualifiedAndroidName: 'com.lastgimbus.the.freebuddy.BatteryWidgetReceiver',
  );
  await HomeWidget.updateWidget(
    name: 'CaseBatteryWidgetReceiver',
    androidName: 'CaseBatteryWidgetReceiver',
    qualifiedAndroidName:
        'com.lastgimbus.the.freebuddy.CaseBatteryWidgetReceiver',
  );
}
