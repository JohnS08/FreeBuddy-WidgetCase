package com.lastgimbus.the.freebuddy

import android.content.Context

object NativeMonitorState {
    const val PREFS = "freebuddy_native_monitor"
    const val CASE_LEVEL = "case_level"
    const val LEFT_LEVEL = "left_level"
    const val RIGHT_LEVEL = "right_level"
    const val CASE_CHARGING = "case_charging"
    const val LEFT_CHARGING = "left_charging"
    const val RIGHT_CHARGING = "right_charging"
    const val UPDATED_AT = "updated_at"
    const val THRESHOLD = "case_battery_threshold"
    const val DEFAULT_THRESHOLD = 20

    fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
