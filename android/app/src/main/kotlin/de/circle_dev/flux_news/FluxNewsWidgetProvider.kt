package de.circle_dev.flux_news

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Base64
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject

class FluxNewsWidgetProvider : AppWidgetProvider() {
  companion object {
    const val PREFS_NAME = "HomeWidgetPreferences"
    const val KEY_SNAPSHOT = "snapshot"
  }

  override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
    for (appWidgetId in appWidgetIds) {
      appWidgetManager.updateAppWidget(appWidgetId, buildViews(context, appWidgetId))
      appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_list)
    }
  }

  private fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
    val views = RemoteViews(context.packageName, R.layout.flux_news_widget)
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val snapshot = JSONObject(prefs.getString(KEY_SNAPSHOT, "{}") ?: "{}")
    val count = snapshot.optInt("unreadCount", 0)
    val countLabel = snapshot.optString("countLabel", "Unread")
    val displayTitle = snapshot.optString("displayTitle", "All News")
    val lastSyncLabel = snapshot.optString("lastSyncLabel", "Last sync")
    val neverLabel = snapshot.optString("neverLabel", "never")
    val syncLabel = snapshot.optString("syncLabel", "Sync")
    val translucentBackground = snapshot.optBoolean("translucentBackground", false)

    views.setInt(
      R.id.widget_root,
      "setBackgroundResource",
      if (translucentBackground) R.drawable.flux_news_widget_background_translucent else R.drawable.flux_news_widget_background,
    )
    views.setTextViewText(R.id.widget_title, displayTitle)
    views.setTextViewText(R.id.widget_count, count.toString())
    views.setTextViewText(R.id.widget_count_label, countLabel)
    views.setTextViewText(
      R.id.widget_last_sync,
      formatLastUpdated(snapshot.optString("lastUpdated", ""), lastSyncLabel, neverLabel),
    )
    views.setContentDescription(R.id.widget_sync_button, syncLabel)
    views.setOnClickPendingIntent(R.id.widget_sync_button, pendingIntent(context, "fluxnews://widget/sync", 9000))

    val listIntent = Intent(context, FluxNewsWidgetService::class.java).apply {
      putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
      data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
    }
    views.setRemoteAdapter(R.id.widget_list, listIntent)
    views.setEmptyView(R.id.widget_list, R.id.widget_empty)
    views.setPendingIntentTemplate(
      R.id.widget_list,
      pendingIntentTemplate(context),
    )

    return views
  }

  private fun pendingIntent(context: Context, uri: String, requestCode: Int): PendingIntent {
    val intent = Intent(context, MainActivity::class.java).apply {
      action = Intent.ACTION_VIEW
      data = Uri.parse(uri)
      flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
    }
    return PendingIntent.getActivity(
      context,
      requestCode,
      intent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
  }

  private fun pendingIntentTemplate(context: Context): PendingIntent {
    val intent = Intent(context, MainActivity::class.java).apply {
      action = Intent.ACTION_VIEW
      flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
    }
    return PendingIntent.getActivity(
      context,
      9100,
      intent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
    )
  }

  private fun formatLastUpdated(value: String, lastSyncLabel: String, neverLabel: String): String {
    if (value.isBlank()) return "$lastSyncLabel: $neverLabel"
    val parsed = try {
      SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US).parse(value)
    } catch (_: Exception) {
      null
    } ?: return "$lastSyncLabel: $value"
    val formatter = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.MEDIUM, Locale.getDefault())
    return "$lastSyncLabel: ${formatter.format(parsed)}"
  }
}

class FluxNewsWidgetService : RemoteViewsService() {
  override fun onGetViewFactory(intent: Intent): RemoteViewsService.RemoteViewsFactory {
    return FluxNewsWidgetFactory(applicationContext)
  }
}

class FluxNewsWidgetFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {
  private var items = JSONArray()

  override fun onCreate() = Unit

  override fun onDataSetChanged() {
    val prefs = context.getSharedPreferences(FluxNewsWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE)
    val snapshot = JSONObject(prefs.getString(FluxNewsWidgetProvider.KEY_SNAPSHOT, "{}") ?: "{}")
    items = snapshot.optJSONArray("items") ?: JSONArray()
  }

  override fun onDestroy() {
    items = JSONArray()
  }

  override fun getCount(): Int = items.length()

  override fun getViewAt(position: Int): RemoteViews {
    val item = items.optJSONObject(position) ?: JSONObject()
    val newsID = item.optInt("id")
    val views = RemoteViews(context.packageName, R.layout.flux_news_widget_list_item)
    views.setTextViewText(R.id.widget_list_item_title, item.optString("title", ""))
    views.setTextViewText(R.id.widget_list_item_feed, item.optString("feedTitle", ""))
    setFeedIcon(views, item)
    val fillInIntent = Intent().apply {
      action = Intent.ACTION_VIEW
      data = Uri.parse("fluxnews://widget/openNews?newsID=$newsID")
    }
    views.setOnClickFillInIntent(R.id.widget_list_item, fillInIntent)
    return views
  }

  override fun getLoadingView(): RemoteViews? = null

  override fun getViewTypeCount(): Int = 1

  override fun getItemId(position: Int): Long =
    items.optJSONObject(position)?.optLong("id") ?: position.toLong()

  override fun hasStableIds(): Boolean = true

  private fun setFeedIcon(views: RemoteViews, item: JSONObject) {
    val iconData = item.optString("iconData", "")
    if (iconData.isNotBlank()) {
      val bytes = Base64.decode(iconData, Base64.DEFAULT)
      val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
      if (bitmap != null) {
        views.setViewVisibility(R.id.widget_list_item_icon, View.VISIBLE)
        views.setViewVisibility(R.id.widget_list_item_icon_frame, View.VISIBLE)
        views.setViewVisibility(R.id.widget_list_item_initial, View.GONE)
        views.setImageViewBitmap(R.id.widget_list_item_icon, bitmap)
        setIconFrameBackground(views, item)
        return
      }
    }

    val initial = item.optString("feedInitial", "").take(1).uppercase()
    views.setViewVisibility(R.id.widget_list_item_icon_frame, View.GONE)
    views.setViewVisibility(R.id.widget_list_item_icon, View.GONE)
    views.setViewVisibility(R.id.widget_list_item_initial, View.VISIBLE)
    views.setTextViewText(R.id.widget_list_item_initial, initial)
  }

  private fun setIconFrameBackground(views: RemoteViews, item: JSONObject) {
    val nightMode = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
    val darkModeEnabled = nightMode == Configuration.UI_MODE_NIGHT_YES
    val adaptInDarkMode = item.optBoolean("manualAdaptDarkModeToIcon", false)
    val adaptInLightMode = item.optBoolean("manualAdaptLightModeToIcon", false)
    val background = when {
      darkModeEnabled && adaptInDarkMode -> R.drawable.flux_news_widget_icon_light_background
      !darkModeEnabled && adaptInLightMode -> R.drawable.flux_news_widget_icon_light_background
      else -> 0
    }

    if (background == 0) {
      views.setInt(R.id.widget_list_item_icon_frame, "setBackgroundColor", 0x00000000)
    } else {
      views.setInt(R.id.widget_list_item_icon_frame, "setBackgroundResource", background)
    }
  }
}
