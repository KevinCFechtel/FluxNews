package de.circledev.fluxnews.nativeapp

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import de.circle_dev.flux_news.FluxNewsWidgetProvider

class AndroidWidgetConfigurationActivity : ComponentActivity() {
    private val appWidgetId: Int by lazy {
        intent?.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(Activity.RESULT_CANCELED)
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val configurationStore = AndroidWidgetConfigurationStore(applicationContext)
        val projectionReader = AndroidWidgetProjectionReader(
            AndroidStoragePaths.create(applicationContext).widget,
        )
        val existing = configurationStore.read(appWidgetId)
        val catalog = projectionReader.catalog()

        setContent {
            FluxNewsTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    AndroidWidgetConfigurationScreen(
                        initial = existing,
                        catalog = catalog,
                        onSave = { configuration ->
                            configurationStore.write(appWidgetId, configuration)
                            FluxNewsWidgetProvider.updateWidget(
                                applicationContext,
                                AppWidgetManager.getInstance(applicationContext),
                                appWidgetId,
                            )
                            setResult(
                                Activity.RESULT_OK,
                                Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId),
                            )
                            finish()
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun AndroidWidgetConfigurationScreen(
    initial: AndroidWidgetConfiguration,
    catalog: AndroidWidgetCatalog,
    onSave: (AndroidWidgetConfiguration) -> Unit,
) {
    val normalizedInitialScopeId = when (initial.scopeType) {
        AndroidWidgetScopeType.Category ->
            initial.scopeId?.takeIf { id -> catalog.categories.any { it.id == id } }
                ?: catalog.categories.firstOrNull()?.id
        AndroidWidgetScopeType.Feed ->
            initial.scopeId?.takeIf { id -> catalog.feeds.any { it.id == id } }
                ?: catalog.feeds.firstOrNull()?.id
        else -> null
    }
    var scopeType by remember {
        mutableStateOf(
            when (initial.scopeType) {
                AndroidWidgetScopeType.Category -> if (catalog.categories.isEmpty()) AndroidWidgetScopeType.All else initial.scopeType
                AndroidWidgetScopeType.Feed -> if (catalog.feeds.isEmpty()) AndroidWidgetScopeType.All else initial.scopeType
                else -> initial.scopeType
            },
        )
    }
    var scopeId by remember { mutableStateOf(normalizedInitialScopeId) }
    var readFilter by remember { mutableStateOf(initial.readFilter) }
    var sortOrder by remember { mutableStateOf(initial.sortOrder) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Text(stringResource(R.string.widget_configuration_title), style = MaterialTheme.typography.headlineSmall)

        WidgetConfigurationSection(title = stringResource(R.string.widget_scope)) {
            WidgetRadioRow(stringResource(R.string.widget_all_news), scopeType == AndroidWidgetScopeType.All) {
                scopeType = AndroidWidgetScopeType.All
                scopeId = null
            }
            WidgetRadioRow(stringResource(R.string.widget_bookmarks), scopeType == AndroidWidgetScopeType.Bookmarks) {
                scopeType = AndroidWidgetScopeType.Bookmarks
                scopeId = null
            }
            WidgetRadioRow(
                stringResource(R.string.widget_category),
                scopeType == AndroidWidgetScopeType.Category,
                enabled = catalog.categories.isNotEmpty(),
            ) {
                scopeType = AndroidWidgetScopeType.Category
                if (catalog.categories.none { it.id == scopeId }) scopeId = catalog.categories.firstOrNull()?.id
            }
            if (scopeType == AndroidWidgetScopeType.Category && catalog.categories.isNotEmpty()) {
                WidgetCatalogPicker(
                    selectedId = scopeId,
                    items = catalog.categories,
                    onSelected = { scopeId = it },
                )
            }
            WidgetRadioRow(
                stringResource(R.string.widget_feed),
                scopeType == AndroidWidgetScopeType.Feed,
                enabled = catalog.feeds.isNotEmpty(),
            ) {
                scopeType = AndroidWidgetScopeType.Feed
                if (catalog.feeds.none { it.id == scopeId }) scopeId = catalog.feeds.firstOrNull()?.id
            }
            if (scopeType == AndroidWidgetScopeType.Feed && catalog.feeds.isNotEmpty()) {
                WidgetCatalogPicker(
                    selectedId = scopeId,
                    items = catalog.feeds,
                    onSelected = { scopeId = it },
                )
            }
        }

        WidgetConfigurationSection(title = stringResource(R.string.widget_read_filter)) {
            WidgetRadioRow(stringResource(R.string.widget_unread_filter), readFilter == AndroidWidgetReadFilter.Unread) {
                readFilter = AndroidWidgetReadFilter.Unread
            }
            WidgetRadioRow(stringResource(R.string.widget_all_articles), readFilter == AndroidWidgetReadFilter.All) {
                readFilter = AndroidWidgetReadFilter.All
            }
        }

        WidgetConfigurationSection(title = stringResource(R.string.widget_sort_order)) {
            WidgetRadioRow(stringResource(R.string.widget_newest_first), sortOrder == AndroidWidgetSortOrder.NewestFirst) {
                sortOrder = AndroidWidgetSortOrder.NewestFirst
            }
            WidgetRadioRow(stringResource(R.string.widget_oldest_first), sortOrder == AndroidWidgetSortOrder.OldestFirst) {
                sortOrder = AndroidWidgetSortOrder.OldestFirst
            }
        }

        Button(
            onClick = {
                onSave(
                    AndroidWidgetConfiguration(
                        scopeType = scopeType,
                        scopeId = when (scopeType) {
                            AndroidWidgetScopeType.Category,
                            AndroidWidgetScopeType.Feed,
                            -> scopeId
                            else -> null
                        },
                        readFilter = readFilter,
                        sortOrder = sortOrder,
                    ),
                )
            },
            enabled = when (scopeType) {
                AndroidWidgetScopeType.Category,
                AndroidWidgetScopeType.Feed,
                -> scopeId != null
                else -> true
            },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(stringResource(R.string.widget_add))
        }
    }
}

@Composable
private fun WidgetConfigurationSection(
    title: String,
    content: @Composable () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        content()
    }
}

@Composable
private fun WidgetRadioRow(
    label: String,
    selected: Boolean,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(selected = selected, onClick = onClick, enabled = enabled)
        Text(
            label,
            color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun WidgetCatalogPicker(
    selectedId: Long?,
    items: List<AndroidWidgetCatalogItem>,
    onSelected: (Long) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val selected = items.firstOrNull { it.id == selectedId } ?: items.firstOrNull()

    Column {
        Button(
            onClick = { expanded = true },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(selected?.title ?: stringResource(R.string.widget_choose))
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            items.forEach { item ->
                DropdownMenuItem(
                    text = { Text(item.title) },
                    onClick = {
                        onSelected(item.id)
                        expanded = false
                    },
                )
            }
        }
    }
}
