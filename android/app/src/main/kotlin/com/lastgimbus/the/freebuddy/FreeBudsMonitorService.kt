package com.lastgimbus.the.freebuddy

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.glance.appwidget.GlanceAppWidgetManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class FreeBudsMonitorService : Service() {
    companion object {
        const val ACTION_START = "com.lastgimbus.the.freebuddy.action.START_MONITOR"
        const val ACTION_STOP = "com.lastgimbus.the.freebuddy.action.STOP_MONITOR"
        const val ACTION_STATE_UPDATED = "com.lastgimbus.the.freebuddy.action.STATE_UPDATED"

        private const val FOREGROUND_ID = 43929
        private const val LOW_BATTERY_ID = 43930
        private const val FOREGROUND_CHANNEL = "freebuddy_native_foreground"
        private const val LOW_BATTERY_CHANNEL = "case_battery_low_native"
        private const val TICK_MS = 60_000L
    }

    private lateinit var workerThread: HandlerThread
    private lateinit var worker: Handler
    private lateinit var notificationManager: NotificationManager
    private val widgetScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val bluetoothScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private lateinit var bluetoothWorker: FreeBudsRfcommWorker
    private var pollJob: Job? = null

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        createChannels()
        workerThread = HandlerThread("FreeBudsMonitor").also { it.start() }
        worker = Handler(workerThread.looper)
        bluetoothWorker = FreeBudsRfcommWorker(this)
        startForegroundCompat()
        scheduleMaintenance()
        scheduleBluetoothPoll(0L)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            ACTION_STATE_UPDATED -> worker.post { refreshNativeOutputs() }
            ACTION_START, null -> scheduleBluetoothPoll(0L)
        }
        return START_STICKY
    }

    private fun scheduleMaintenance() {
        worker.postDelayed(object : Runnable {
            override fun run() {
                scheduleBluetoothPoll(0L)
                worker.postDelayed(this, TICK_MS)
            }
        }, TICK_MS)
    }

    private fun scheduleBluetoothPoll(delayMillis: Long) {
        worker.postDelayed({
            if (pollJob?.isActive != true) {
                pollJob = bluetoothScope.launch {
                    val state = bluetoothWorker.poll()
                    if (state != null) {
                        persistBatteryState(state)
                        withContext(Dispatchers.Main.immediate) {
                            refreshNativeOutputs()
                        }
                    }
                }
            }
        }, delayMillis)
    }

    private fun persistBatteryState(state: FreeBudsRfcommWorker.BatteryState) {
        NativeMonitorState.prefs(this).edit()
            .putInt(NativeMonitorState.LEFT_LEVEL, state.left ?: -1)
            .putInt(NativeMonitorState.RIGHT_LEVEL, state.right ?: -1)
            .putInt(NativeMonitorState.CASE_LEVEL, state.case ?: -1)
            .putBoolean(NativeMonitorState.LEFT_CHARGING, state.leftCharging)
            .putBoolean(NativeMonitorState.RIGHT_CHARGING, state.rightCharging)
            .putBoolean(NativeMonitorState.CASE_CHARGING, state.caseCharging)
            .putLong(NativeMonitorState.UPDATED_AT, System.currentTimeMillis())
            .apply()
    }

    /** The native service is the sole owner of background output delivery. */
    private fun refreshNativeOutputs() {
        updateWidgets()
        postLowBatteryNotificationIfNeeded()
    }

    private fun startForegroundCompat() {
        val notification = NotificationCompat.Builder(this, FOREGROUND_CHANNEL)
            .setSmallIcon(com.lastgimbus.the.freebuddy.R.mipmap.ic_launcher)
            .setContentTitle("FreeBuddy работает в фоне")
            .setContentText("Мониторинг заряда кейса включён")
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setShowWhen(false)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                FOREGROUND_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            startForeground(FOREGROUND_ID, notification)
        }
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        notificationManager.createNotificationChannel(
            NotificationChannel(
                FOREGROUND_CHANNEL,
                "FreeBuddy работает в фоне",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Фоновый мониторинг FreeBuds" },
        )
        notificationManager.createNotificationChannel(
            NotificationChannel(
                LOW_BATTERY_CHANNEL,
                "Заряд кейса",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Уведомления о низком заряде кейса FreeBuds"
                enableVibration(true)
                setSound(
                    android.provider.Settings.System.DEFAULT_NOTIFICATION_URI,
                    android.media.AudioAttributes.Builder()
                        .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION)
                        .build(),
                )
            },
        )
    }

    private fun postLowBatteryNotificationIfNeeded() {
        val prefs = NativeMonitorState.prefs(this)
        val level = prefs.getInt(NativeMonitorState.CASE_LEVEL, -1)
        val charging = prefs.getBoolean(NativeMonitorState.CASE_CHARGING, false)
        val threshold = prefs.getInt(
            NativeMonitorState.THRESHOLD,
            NativeMonitorState.DEFAULT_THRESHOLD,
        )
        if (level < 0 || charging || level > threshold) return
        notificationManager.notify(
            LOW_BATTERY_ID,
            NotificationCompat.Builder(this, LOW_BATTERY_CHANNEL)
                .setSmallIcon(com.lastgimbus.the.freebuddy.R.mipmap.ic_launcher)
                .setContentTitle("Низкий заряд кейса FreeBuds")
                .setContentText("Case FreeBuds: $level%")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setAutoCancel(false)
                .setVibrate(longArrayOf(0, 300, 200, 300))
                .build(),
        )
    }

    private fun updateWidgets() {
        widgetScope.launch {
            val manager = GlanceAppWidgetManager(this@FreeBudsMonitorService)
            manager.getGlanceIds(BatteryWidget::class.java).forEach { id ->
                BatteryWidget().update(this@FreeBudsMonitorService, id)
            }
            manager.getGlanceIds(CaseBatteryWidget::class.java).forEach { id ->
                CaseBatteryWidget().update(this@FreeBudsMonitorService, id)
            }
        }
    }

    override fun onDestroy() {
        worker.removeCallbacksAndMessages(null)
        bluetoothScope.cancel()
        workerThread.quitSafely()
        widgetScope.coroutineContext.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
