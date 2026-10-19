import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../cubit/headphones_cubit_objects.dart';
import '../../../headphones/framework/lrc_battery.dart';
import '../../../logger.dart';
import '../background/foreground_service.dart' as native_service;

// no better idea for this yet - that's fine
StreamSubscription<LRCBatteryLevels>? _headphonesBatteryStreamSub;

void batteryHomeWidgetHearBloc(BuildContext context,
    HeadphonesConnectionState headphonesConnectionState) async {
  if (headphonesConnectionState is! HeadphonesConnectedOpen) {
    await _headphonesBatteryStreamSub?.cancel();
    _headphonesBatteryStreamSub = null;
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
    });
  }
}

// this is separate so we can use it from f.e. background stuff
Future<void> updateBatteryHomeWidget(LRCBatteryLevels batteryData) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('case_last_level', batteryData.levelCase ?? -1);
  await prefs.setBool('case_last_charging', batteryData.chargingCase);
  await native_service.nativeMonitorChannel.invokeMethod<void>('updateState', {
    'left': batteryData.levelLeft ?? -1,
    'right': batteryData.levelRight ?? -1,
    'case': batteryData.levelCase ?? -1,
    'leftCharging': batteryData.chargingLeft,
    'rightCharging': batteryData.chargingRight,
    'caseCharging': batteryData.chargingCase,
  });
}
