package com.lastgimbus.the.freebuddy

import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Records Bluetooth ACL transitions for diagnostics. The foreground service
 * performs the actual battery poll; this receiver must remain lightweight and
 * must not enqueue a WorkManager task.
 */
class BluetoothDeviceConnectedReceiver : BroadcastReceiver() {
    companion object {
        const val TAG = "BtDevConnReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val device = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        }
        Log.d(TAG, "Bluetooth ACL event ${intent.action} for $device")
    }
}
