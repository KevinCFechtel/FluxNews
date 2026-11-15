package de.circledev.fluxnews.nativeapp

import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationDrawerItemDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

@Composable
internal fun NewsNavigationContent(
    navigation: NewsNavigationModel,
    preferences: AndroidNavigationPreferenceState,
    timelineStore: AndroidArticleTimelineStore,
    selectedScope: AndroidNewsScope,
    onScopeSelected: (AndroidNewsScope) -> Unit,
    onSearch: () -> Unit,
    onListeningList: () -> Unit,
    onSettings: () -> Unit,
    onFeedSettings: (AndroidNavigationFeedRef) -> Unit,
    onAddFeed: () -> Unit,
    onAddCategory: () -> Unit,
    sidebarMiniPlayer: (@Composable () -> Unit)? = null,
    activeDestination: String = "timeline",
    navigationToggleIcon: Int? = null,
    navigationToggleDescription: String? = null,
    onNavigationToggle: (() -> Unit)? = null,
) {
    var addMenuExpanded by remember { mutableStateOf(false) }
    val projection = navigation.projection
    val timelineState by timelineStore.state.collectAsState()
    val feedIconVariant = if (isSystemInDarkTheme()) {
        uniffi.flux_uniffi.FeedIconVariant.DARK
    } else {
        uniffi.flux_uniffi.FeedIconVariant.NORMAL
    }
    val feedCounts = projection?.feedCounts?.associate { it.id to it.count }.orEmpty()
    val categoryCounts = projection?.categoryCounts?.associate { it.id to it.count }.orEmpty()
    val categoryRefs = projection?.catalog?.categories?.map { AndroidNavigationCategoryRef(it.id, it.title) }.orEmpty()
    val feedRefs = projection?.catalog?.feeds?.map { AndroidNavigationFeedRef(it.id, it.categoryId, it.title) }.orEmpty()
    val policyVisibleFeedIds = AndroidNavigationPolicy.visibleFeedIds(
        preferences.hideEmptyNavigationEntries,
        feedRefs,
        feedCounts,
    )
    // New feeds may have zero unread items. Keep the selected feed/category
    // visible even when the user hides empty navigation entries.
    val selectedFeedId = (selectedScope as? AndroidNewsScope.Feed)?.id
    val visibleFeedIds = policyVisibleFeedIds + listOfNotNull(selectedFeedId)
    val policyVisibleCategoryIds = if (preferences.hideEmptyNavigationEntries) {
        AndroidNavigationPolicy.visibleCategoryIds(categoryRefs, feedRefs, visibleFeedIds)
    } else {
        categoryRefs.mapTo(mutableSetOf()) { it.id }
    }
    val visibleCategoryIds = policyVisibleCategoryIds +
        listOfNotNull((selectedScope as? AndroidNewsScope.Category)?.id)
    var expandedCategories by remember { mutableStateOf(setOf<Long>()) }
    val darkMode = isSystemInDarkTheme()
    val selectedDrawerContainer = if (darkMode) {
        MaterialTheme.colorScheme.background
    } else {
        MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.42f)
    }
    val drawerItemColors = NavigationDrawerItemDefaults.colors(
        selectedContainerColor = selectedDrawerContainer,
        unselectedContainerColor = MaterialTheme.colorScheme.background,
        selectedIconColor = MaterialTheme.colorScheme.primary,
        selectedTextColor = MaterialTheme.colorScheme.primary,
        unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
        unselectedTextColor = MaterialTheme.colorScheme.onSurface,
    )

    LaunchedEffect(selectedScope, projection) {
        if (selectedScope is AndroidNewsScope.Feed) {
            expandedCategories = expandedCategories + selectedScope.categoryId
        }
    }

    Column(modifier = Modifier.fillMaxHeight().padding(horizontal = 12.dp)) {
        Column(modifier = Modifier.weight(1f).verticalScroll(rememberScrollState())) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 20.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                painter = painterResource(R.drawable.ic_fluxnews_logo),
                contentDescription = null,
                modifier = Modifier.size(30.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
            Text(
                "FluxNews",
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
            )
            if (navigationToggleIcon != null && onNavigationToggle != null) {
                IconButton(onClick = onNavigationToggle) {
                    Icon(
                        painter = painterResource(navigationToggleIcon),
                        contentDescription = navigationToggleDescription ?: stringResource(R.string.nav_toggle),
                    )
                }
            }
        }
        Text(
            stringResource(R.string.nav_news),
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
        )
        NavigationDrawerItem(
            label = { DrawerLabel(stringResource(R.string.nav_all_news), projection?.unreadTotal ?: 0uL) },
            selected = activeDestination == "timeline" && selectedScope == AndroidNewsScope.All,
            onClick = { onScopeSelected(AndroidNewsScope.All) },
            icon = { DrawerIcon(R.drawable.ic_news, stringResource(R.string.nav_all_news)) },
            colors = drawerItemColors,
        )
        NavigationDrawerItem(
            label = { DrawerLabel(stringResource(R.string.nav_starred), projection?.starredTotal ?: 0uL) },
            selected = activeDestination == "timeline" && selectedScope == AndroidNewsScope.Starred,
            onClick = { onScopeSelected(AndroidNewsScope.Starred) },
            icon = { DrawerIcon(R.drawable.ic_star, stringResource(R.string.nav_starred)) },
            colors = drawerItemColors,
        )
        NavigationDrawerItem(
            label = { Text(stringResource(R.string.nav_listening_list)) },
            selected = activeDestination == "listening-list",
            onClick = onListeningList,
            icon = { DrawerIcon(R.drawable.ic_headphones, stringResource(R.string.nav_listening_list)) },
            colors = drawerItemColors,
        )
        NavigationDrawerItem(
            label = { Text(stringResource(R.string.nav_search)) },
            selected = activeDestination == "search",
            onClick = onSearch,
            icon = { DrawerIcon(R.drawable.ic_search, stringResource(R.string.nav_search)) },
            colors = drawerItemColors,
        )

        HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))
        Row(
            modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                stringResource(R.string.nav_feeds),
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            Box {
                IconButton(onClick = { addMenuExpanded = true }) {
                    Icon(
                        imageVector = Icons.Rounded.Add,
                        contentDescription = stringResource(R.string.nav_add_feed_short) +
                            " / " + stringResource(R.string.nav_add_category_short),
                    )
                }
                DropdownMenu(
                    expanded = addMenuExpanded,
                    onDismissRequest = { addMenuExpanded = false },
                ) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.nav_add_feed_short)) },
                        onClick = {
                            addMenuExpanded = false
                            onAddFeed()
                        },
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.nav_add_category_short)) },
                        onClick = {
                            addMenuExpanded = false
                            onAddCategory()
                        },
                    )
                }
            }
        }

        if (projection == null) {
            Text(
                navigation.error ?: stringResource(R.string.nav_loading_feeds),
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            projection.catalog.categories
                .filter { it.id in visibleCategoryIds }
                .forEach { category ->
                    val categoryScope = AndroidNewsScope.Category(category.id, category.title)
                    val expanded = category.id in expandedCategories
                    CategoryNavigationRow(
                        title = category.title,
                        count = categoryCounts[category.id] ?: 0uL,
                        selected = activeDestination == "timeline" && selectedScope == categoryScope,
                        containsSelectedFeed = selectedScope is AndroidNewsScope.Feed && selectedScope.categoryId == category.id,
                        expanded = expanded,
                        onToggleExpanded = {
                            expandedCategories = if (expanded) expandedCategories - category.id else expandedCategories + category.id
                        },
                        onSelected = { onScopeSelected(categoryScope) },
                    )
                    if (expanded) {
                        projection.catalog.feeds
                            .filter { it.categoryId == category.id && it.id in visibleFeedIds }
                            .forEach { feed ->
                                val feedScope = AndroidNewsScope.Feed(feed.id, feed.categoryId, feed.title)
                                FeedNavigationRow(
                                    feedId = feed.id,
                                    title = feed.title,
                                    count = feedCounts[feed.id] ?: 0uL,
                                    selected = activeDestination == "timeline" && selectedScope == feedScope,
                                    iconPng = timelineState.feedIconPngByFeedId[feed.id],
                                    iconVariant = feedIconVariant,
                                    onRequestFeedIcon = timelineStore::ensureFeedIcon,
                                    onClick = { onScopeSelected(feedScope) },
                                    onSettings = { onFeedSettings(AndroidNavigationFeedRef(feed.id, feed.categoryId, feed.title)) },
                                )
                            }
                    }
                }

            val knownCategoryIds = projection.catalog.categories.mapTo(mutableSetOf()) { it.id }
            projection.catalog.feeds
                .filter { it.categoryId !in knownCategoryIds && it.id in visibleFeedIds }
                .forEach { feed ->
                    val feedScope = AndroidNewsScope.Feed(feed.id, feed.categoryId, feed.title)
                    FeedNavigationRow(
                        feedId = feed.id,
                        title = feed.title,
                        count = feedCounts[feed.id] ?: 0uL,
                        selected = activeDestination == "timeline" && selectedScope == feedScope,
                        iconPng = timelineState.feedIconPngByFeedId[feed.id],
                        iconVariant = feedIconVariant,
                        onRequestFeedIcon = timelineStore::ensureFeedIcon,
                        onClick = { onScopeSelected(feedScope) },
                        onSettings = { onFeedSettings(AndroidNavigationFeedRef(feed.id, feed.categoryId, feed.title)) },
                    )
                }
        }

        Spacer(Modifier.height(12.dp))
        HorizontalDivider()
        NavigationDrawerItem(
            label = { Text(stringResource(R.string.nav_settings)) },
            selected = false,
            onClick = onSettings,
            icon = { DrawerIcon(R.drawable.ic_settings, stringResource(R.string.nav_settings)) },
            colors = drawerItemColors,
            modifier = Modifier.padding(top = 8.dp, bottom = 16.dp),
        )
        }
        if (sidebarMiniPlayer != null) {
            sidebarMiniPlayer()
        }
    }
}

@Composable
private fun CategoryNavigationRow(
    title: String,
    count: ULong,
    selected: Boolean,
    containsSelectedFeed: Boolean,
    expanded: Boolean,
    onToggleExpanded: () -> Unit,
    onSelected: () -> Unit,
) {
    val selectedContainer = if (selected && !isSystemInDarkTheme()) {
        MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.42f)
    } else {
        MaterialTheme.colorScheme.background
    }
    Surface(
        color = selectedContainer,
        shape = MaterialTheme.shapes.extraLarge,
        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onToggleExpanded) {
                Icon(
                    painterResource(if (expanded) R.drawable.ic_expand_more else R.drawable.ic_chevron_right),
                    if (expanded) "Collapse $title" else "Expand $title",
                )
            }
            Row(
                modifier = Modifier.weight(1f).clickable(onClick = onSelected).padding(end = 16.dp, top = 14.dp, bottom = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    painterResource(R.drawable.ic_folder),
                    null,
                    tint = if (selected || containsSelectedFeed) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    title,
                    modifier = Modifier.weight(1f).padding(start = 12.dp),
                    fontWeight = if (selected || containsSelectedFeed) FontWeight.Medium else FontWeight.Normal,
                    color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                )
                CountText(count)
            }
        }
    }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun FeedNavigationRow(
    feedId: Long,
    title: String,
    count: ULong,
    selected: Boolean,
    iconPng: ByteArray?,
    iconVariant: uniffi.flux_uniffi.FeedIconVariant,
    onRequestFeedIcon: suspend (Long, uniffi.flux_uniffi.FeedIconVariant) -> Unit,
    onClick: () -> Unit,
    onSettings: () -> Unit,
) {
    val selectedContainer = if (selected && !isSystemInDarkTheme()) {
        MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.42f)
    } else {
        MaterialTheme.colorScheme.background
    }
    val haptics = LocalHapticFeedback.current
    var menuExpanded by remember { mutableStateOf(false) }

    Surface(
        color = selectedContainer,
        shape = MaterialTheme.shapes.extraLarge,
        modifier = Modifier.fillMaxWidth().padding(start = 32.dp, top = 2.dp, bottom = 2.dp),
    ) {
        Box {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .combinedClickable(
                        onClick = onClick,
                        onLongClick = {
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            menuExpanded = true
                        },
                    )
                    .padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                FeedIcon(
                    feedId = feedId,
                    title = title,
                    pngData = iconPng,
                    variant = iconVariant,
                    onRequest = onRequestFeedIcon,
                )
                Text(
                    title,
                    modifier = Modifier.weight(1f).padding(start = 12.dp),
                    fontWeight = if (selected) FontWeight.Medium else FontWeight.Normal,
                    color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                )
                CountText(count)
            }

            DropdownMenu(
                expanded = menuExpanded,
                onDismissRequest = { menuExpanded = false },
            ) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.nav_feed_settings)) },
                    onClick = {
                        menuExpanded = false
                        onSettings()
                    },
                )
            }
        }
    }
}

@Composable
private fun DrawerLabel(title: String, count: ULong) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(title, modifier = Modifier.weight(1f))
        CountText(count)
    }
}

@Composable
private fun CountText(count: ULong) {
    if (count > 0u) {
        Text(
            if (count > 999u) "999+" else count.toString(),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun DrawerIcon(drawable: Int, description: String) {
    Icon(painterResource(drawable), description)
}
