package com.lastgimbus.the.freebuddy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class MonitorBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED &&
            intent?.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val serviceIntent = Intent(context, FreeBudsMonitorService::class.java)
            .setAction(FreeBudsMonitorService.ACTION_START)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
