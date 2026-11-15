package de.circledev.fluxnews.nativeapp

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import de.circle_dev.flux_news.FluxNewsWidgetProvider

internal object AndroidWidgetUpdates {
    fun refreshAll(context: Context) {
        val appContext = context.applicationContext
        val manager = AppWidgetManager.getInstance(appContext)
        val provider = ComponentName(appContext, FluxNewsWidgetProvider::class.java)
        manager.getAppWidgetIds(provider).forEach { widgetId ->
            FluxNewsWidgetProvider.updateWidget(appContext, manager, widgetId)
        }
    }
}
