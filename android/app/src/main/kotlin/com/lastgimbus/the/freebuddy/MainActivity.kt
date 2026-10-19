package com.lastgimbus.the.freebuddy

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.lastgimbus.the.freebuddy/native_monitor"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        startMonitorService()
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, FreeBudsMonitorService::class.java))
                        result.success(null)
                    }
                    "updateState" -> {
                        val args = call.arguments as? Map<*, *>
                        val prefs = NativeMonitorState.prefs(this)
                        prefs.edit()
                            .putInt(NativeMonitorState.LEFT_LEVEL, (args?.get("left") as? Number)?.toInt() ?: -1)
                            .putInt(NativeMonitorState.RIGHT_LEVEL, (args?.get("right") as? Number)?.toInt() ?: -1)
                            .putInt(NativeMonitorState.CASE_LEVEL, (args?.get("case") as? Number)?.toInt() ?: -1)
                            .putBoolean(NativeMonitorState.LEFT_CHARGING, args?.get("leftCharging") as? Boolean ?: false)
                            .putBoolean(NativeMonitorState.RIGHT_CHARGING, args?.get("rightCharging") as? Boolean ?: false)
                            .putBoolean(NativeMonitorState.CASE_CHARGING, args?.get("caseCharging") as? Boolean ?: false)
                            .putLong(NativeMonitorState.UPDATED_AT, System.currentTimeMillis())
                            .apply()
                        startMonitorService()
                        sendStateUpdated()
                        result.success(null)
                    }
                    "setThreshold" -> {
                        val threshold = (call.arguments as? Number)?.toInt()
                        if (threshold != null) {
                            NativeMonitorState.prefs(this).edit()
                                .putInt(NativeMonitorState.THRESHOLD, threshold)
                                .apply()
                            sendStateUpdated()
                        }
                        result.success(null)
                    }
                    "requestBackgroundPermissions" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName"),
                            )
                            runCatching { startActivity(intent) }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startMonitorService() {
        val intent = Intent(this, FreeBudsMonitorService::class.java)
            .setAction(FreeBudsMonitorService.ACTION_START)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun sendStateUpdated() {
        sendServiceAction(FreeBudsMonitorService.ACTION_STATE_UPDATED)
    }

    private fun sendServiceAction(action: String) {
        val intent = Intent(this, FreeBudsMonitorService::class.java).setAction(action)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
