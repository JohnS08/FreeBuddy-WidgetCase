package com.lastgimbus.the.freebuddy

import androidx.glance.appwidget.GlanceAppWidgetReceiver

class BatteryWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = BatteryWidget()
}
