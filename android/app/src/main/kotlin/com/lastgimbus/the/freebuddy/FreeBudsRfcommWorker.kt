package com.lastgimbus.the.freebuddy

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import java.io.BufferedInputStream
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit

class FreeBudsRfcommWorker(private val context: Context) {
    companion object {
        private const val TAG = "FreeBudsRfcomm"
        private const val CONNECT_TIMEOUT_SECONDS = 8L
        private const val READ_TIMEOUT_MILLIS = 8_000
        private const val SPP_UUID = "00001101-0000-1000-8000-00805f9b34fb"
        private val executor = Executors.newCachedThreadPool()
        private val freeBudsName = Regex(".*FreeBuds\\s+(3i|4i|5i).*", RegexOption.IGNORE_CASE)
    }

    data class BatteryState(
        val left: Int?,
        val right: Int?,
        val case: Int?,
        val leftCharging: Boolean,
        val rightCharging: Boolean,
        val caseCharging: Boolean,
    )

    fun poll(): BatteryState? {
        if (!hasBluetoothPermission()) return null
        val adapter = bluetoothAdapter() ?: return null
        if (!adapter.isEnabled) return null
        if (adapter.getProfileConnectionState(android.bluetooth.BluetoothProfile.A2DP) !=
            android.bluetooth.BluetoothProfile.STATE_CONNECTED &&
            adapter.getProfileConnectionState(android.bluetooth.BluetoothProfile.HEADSET) !=
            android.bluetooth.BluetoothProfile.STATE_CONNECTED) return null
        val device = adapter.bondedDevices.firstOrNull { freeBudsName.matches(it.name ?: "") }
            ?: return null
        return connectAndRead(device)
    }

    private fun connectAndRead(device: BluetoothDevice): BatteryState? {
        var socket: BluetoothSocket? = null
        var task: Future<BatteryState?>? = null
        return try {
            val activeSocket = device.createRfcommSocketToServiceRecord(UUID.fromString(SPP_UUID))
            socket = activeSocket
            task = executor.submit<BatteryState?> {
                activeSocket.connect()
                val output = activeSocket.outputStream
                output.write(queryBattery())
                output.flush()
                readBattery(activeSocket)
            }
            task.get(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        } catch (error: Exception) {
            Log.w(TAG, "RFCOMM poll failed for ${device.name}", error)
            task?.cancel(true)
            null
        } finally {
            try { socket?.close() } catch (_: IOException) {}
        }
    }

    private fun readBattery(socket: BluetoothSocket): BatteryState? {
        val input = BufferedInputStream(socket.inputStream)
        val first = ByteArray(3)
        readFully(input, first, READ_TIMEOUT_MILLIS) ?: return null
        val length = first[2].toInt() and 0xff
        if (first[0].toInt() and 0xff != 0x5a || length < 3 || length > 250) return null
        val remaining = ByteArray(length + 2)
        readFully(input, remaining, READ_TIMEOUT_MILLIS) ?: return null
        val frame = first + remaining
        if (!verifyCrc(frame)) return null
        val service = frame[4].toInt() and 0xff
        val command = frame[5].toInt() and 0xff
        if (service != 1 || (command != 8 && command != 39)) return null
        return parseBattery(frame)
    }

    private fun parseBattery(frame: ByteArray): BatteryState? {
        val end = frame.size - 2
        var offset = 6
        var levels: ByteArray? = null
        var charging: ByteArray? = null
        while (offset + 2 <= end) {
            val id = frame[offset].toInt() and 0xff
            val size = frame[offset + 1].toInt() and 0xff
            offset += 2
            if (size > end - offset) return null
            val value = frame.copyOfRange(offset, offset + size)
            when (id) {
                2 -> levels = value
                3 -> charging = value
            }
            offset += size
        }
        if (levels == null || levels.size < 3 || charging == null || charging.size < 3) return null
        return BatteryState(
            levelOrNull(levels[0]),
            levelOrNull(levels[1]),
            levelOrNull(levels[2]),
            charging[0].toInt() != 0,
            charging[1].toInt() != 0,
            charging[2].toInt() != 0,
        )
    }

    private fun queryBattery(): ByteArray {
        val body = byteArrayOf(0x5a, 0x00, 0x03, 0x00, 0x01, 0x08)
        return body + crc(body)
    }

    private fun verifyCrc(frame: ByteArray): Boolean {
        if (frame.size < 8) return false
        val expected = crc(frame.copyOf(frame.size - 2))
        return expected[0] == frame[frame.size - 2] &&
            expected[1] == frame[frame.size - 1]
    }

    private fun crc(data: ByteArray): ByteArray {
        var crc = 0
        for (byte in data) {
            crc = crc xor ((byte.toInt() and 0xff) shl 8)
            repeat(8) {
                crc = if ((crc and 0x8000) != 0) {
                    (crc shl 1) xor 0x1021
                } else {
                    crc shl 1
                }
                crc = crc and 0xffff
            }
        }
        return byteArrayOf((crc ushr 8).toByte(), crc.toByte())
    }

    private fun readFully(input: BufferedInputStream, buffer: ByteArray, timeoutMillis: Int): ByteArray? {
        val deadline = System.currentTimeMillis() + timeoutMillis
        var offset = 0
        while (offset < buffer.size && System.currentTimeMillis() < deadline) {
            val available = input.available()
            if (available <= 0) {
                Thread.sleep(10)
                continue
            }
            val count = input.read(buffer, offset, buffer.size - offset)
            if (count < 0) return null
            offset += count
        }
        return if (offset == buffer.size) buffer else null
    }

    private fun levelOrNull(value: Byte): Int? {
        val level = value.toInt() and 0xff
        return if (level == 0) null else level.coerceIn(0, 100)
    }

    private fun bluetoothAdapter(): BluetoothAdapter? {
        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? android.bluetooth.BluetoothManager
        return manager?.adapter
    }

    private fun hasBluetoothPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
    }
}
