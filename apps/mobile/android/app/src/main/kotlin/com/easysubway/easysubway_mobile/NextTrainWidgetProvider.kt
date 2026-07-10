package com.easysubway.easysubway_mobile

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import androidx.work.WorkManager
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class NextTrainWidgetProvider : HomeWidgetProvider() {
    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        WorkManager.getInstance(context).cancelUniqueWork("next-train-widget-refresh")
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val prefix = "widget_${widgetId}_"
            val stationId = widgetData.getString("${prefix}station_id", "").orEmpty()
            val lineId = widgetData.getString("${prefix}line_id", "").orEmpty()
            val stationName = widgetData.getString("widget_${widgetId}_station_name", "역을 선택해 주세요").orEmpty()
            val lineName = widgetData.getString("${prefix}line_name", "").orEmpty()
            val status = widgetData.getString("${prefix}status", "timetableUnavailable").orEmpty()
            val detailUri = Uri.parse("easysubway://station/detail").buildUpon()
                .appendQueryParameter("stationId", stationId)
                .appendQueryParameter("lineId", lineId)
                .build()
            val views = RemoteViews(context.packageName, R.layout.next_train_widget).apply {
                setTextViewText(R.id.widget_station_name, stationName)
                setTextViewText(R.id.widget_line_name, lineName)
                setTextViewText(R.id.widget_direction_1, widgetData.getString("${prefix}direction_1", ""))
                setTextViewText(R.id.widget_departure_1, widgetData.getString("${prefix}departure_1", ""))
                setTextViewText(R.id.widget_direction_2, widgetData.getString("${prefix}direction_2", ""))
                setTextViewText(R.id.widget_departure_2, widgetData.getString("${prefix}departure_2", ""))
                setTextViewText(R.id.widget_status, widgetData.getString("${prefix}status_label", "시간표를 확인할 수 없어요."))
                setViewVisibility(
                    R.id.widget_departures,
                    if (status == "timetableUnavailable") View.GONE else View.VISIBLE,
                )
                setOnClickPendingIntent(
                    R.id.widget_container,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, detailUri),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
