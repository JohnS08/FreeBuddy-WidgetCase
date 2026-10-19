package com.lastgimbus.the.freebuddy

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.*
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.*
import androidx.glance.layout.*
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextDefaults
import androidx.glance.unit.ColorProvider

class CaseBatteryWidget : GlanceAppWidget() {
    companion object {
        private val COMPACT = DpSize(60.dp, 60.dp)
        private val WIDE = DpSize(120.dp, 60.dp)
    }

    override val sizeMode = SizeMode.Responsive(setOf(COMPACT, WIDE))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val prefs = NativeMonitorState.prefs(context)
        provideContent {
            Content(
                context,
                prefs.getInt(NativeMonitorState.CASE_LEVEL, -1),
                prefs.getBoolean(NativeMonitorState.CASE_CHARGING, false),
            )
        }
    }

    @Composable
    private fun Content(context: Context, level: Int, charging: Boolean) {
        val size = LocalSize.current
        val textStyle = TextDefaults.defaultTextStyle.copy(
            color = ColorProvider(R.color.battery_widget_text_color),
            fontWeight = FontWeight.Medium,
            fontSize = if (size.width <= COMPACT.width) 15.sp else 17.sp,
            textAlign = TextAlign.Center,
        )
        Box(
            modifier = GlanceModifier.fillMaxSize()
                .appWidgetBackground()
                .clickable(actionStartActivity(activity = MainActivity::class.java))
                .background(GlanceTheme.colors.background)
                .cornerRadius(R.dimen.batteryWidgetBackgroundRadius)
                .padding(6.dp),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                modifier = GlanceModifier.fillMaxSize(),
                verticalAlignment = Alignment.Vertical.CenterVertically,
                horizontalAlignment = Alignment.Horizontal.CenterHorizontally,
            ) {
                Image(
                    provider = ImageProvider(R.drawable.earbuds_case),
                    contentDescription = "Case",
                    modifier = GlanceModifier.size(if (size.width <= COMPACT.width) 24.dp else 28.dp),
                    colorFilter = ColorFilter.tint(GlanceTheme.colors.primary),
                )
                Spacer(modifier = GlanceModifier.height(2.dp))
                Text(
                    text = when {
                        level < 0 -> "—"
                        charging -> "$level% ⚡"
                        else -> "$level%"
                    },
                    style = textStyle,
                )
            }
        }
    }
}
