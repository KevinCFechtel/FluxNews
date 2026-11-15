package de.circledev.fluxnews.nativeapp

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import uniffi.flux_uniffi.CreateFeedRequest
import uniffi.flux_uniffi.DiscoverSubscriptionsRequest
import uniffi.flux_uniffi.DiscoveredSubscription
import java.net.URI

/** Mirrors the existing iOS discovery -> choose feed -> create contract. */
internal object AndroidFeedCreationPolicy {
    fun validUrl(input: String): String? {
        val trimmed = input.trim()
        val uri = runCatching { URI(trimmed) }.getOrNull() ?: return null
        return trimmed.takeIf {
            uri.scheme?.lowercase() in setOf("http", "https") &&
                !uri.host.isNullOrBlank() && uri.rawUserInfo == null
        }
    }

    fun categoryTitle(input: String): String? = input.trim().takeIf(String::isNotEmpty)

    fun isDuplicateCategory(title: String, existing: List<AndroidNavigationCategoryRef>): Boolean =
        existing.any { it.title.trim().equals(title.trim(), ignoreCase = true) }

    fun failureResource(error: Throwable, isFeed: Boolean): Int {
        val description = error.message.orEmpty()
        return when {
            listOf("already exists", "already subscribed", "duplicate", "409").any { description.contains(it, ignoreCase = true) } ->
                if (isFeed) R.string.feed_already_subscribed else R.string.feed_category_already_exists
            listOf("unauthorized", "authentication").any { description.contains(it, ignoreCase = true) } ->
                R.string.feed_auth_failed
            listOf("connect", "network", "timeout").any { description.contains(it, ignoreCase = true) } ->
                R.string.feed_connection_failed
            isFeed -> R.string.feed_create_failed
            else -> R.string.feed_category_create_failed
        }
    }

    fun failureMessage(error: Throwable, isFeed: Boolean): String {
        val description = error.message.orEmpty()
        if (description.contains("already exists", ignoreCase = true) ||
            description.contains("already subscribed", ignoreCase = true) ||
            description.contains("duplicate", ignoreCase = true) ||
            description.contains("409")
        ) {
            return if (isFeed) "This feed is already subscribed." else "This category already exists."
        }
        if (description.contains("unauthorized", ignoreCase = true) ||
            description.contains("authentication", ignoreCase = true)
        ) return "Miniflux authentication failed. Check your account."
        if (description.contains("connect", ignoreCase = true) ||
            description.contains("network", ignoreCase = true) ||
            description.contains("timeout", ignoreCase = true)
        ) return "Could not connect to Miniflux. Check your connection and try again."
        return if (isFeed) "Miniflux could not add this feed. Check the URL and try again."
        else "Miniflux could not add this category. Try another name."
    }
}

internal sealed interface AndroidCreatedNavigationItem {
    data class Feed(val id: Long) : AndroidCreatedNavigationItem
    data class Category(val id: Long) : AndroidCreatedNavigationItem
}

/**
 * All server mutations go through the existing UniFFI Core on a remote worker.
 * Once created, the shell schedules a full Core Sync before selecting the new item.
 */
@Composable
internal fun AndroidAddFeedDialog(
    coreRuntime: AndroidCoreRuntime,
    sessionGeneration: Long,
    categories: List<AndroidNavigationCategoryRef>,
    onDismiss: () -> Unit,
    onCreated: (AndroidCreatedNavigationItem) -> Unit,
) {
    val scope = rememberCoroutineScope()
    var url by remember { mutableStateOf("") }
    var categoryId by remember { mutableStateOf<Long?>(null) }
    var categoryMenuExpanded by remember { mutableStateOf(false) }
    var candidates by remember { mutableStateOf<List<DiscoveredSubscription>>(emptyList()) }
    var selectedCandidate by remember { mutableIntStateOf(0) }
    var working by remember { mutableStateOf(false) }
    var errorResource by remember { mutableStateOf<Int?>(null) }
    val normalizedUrl = AndroidFeedCreationPolicy.validUrl(url)
    val categoryLabel = categories.firstOrNull { it.id == categoryId }?.title ?: stringResource(R.string.feed_default_category)

    suspend fun create(feedUrl: String) {
        working = true
        errorResource = null
        runCatching {
            coreRuntime.remoteForGeneration(sessionGeneration) { core ->
                core.createFeed(
                    CreateFeedRequest(
                        feedUrl = feedUrl,
                        categoryId = categoryId,
                        username = null,
                        password = null,
                        crawler = null,
                        userAgent = null,
                        scraperRules = null,
                        rewriteRules = null,
                        blocklistRules = null,
                        keeplistRules = null,
                        disabled = null,
                        ignoreHttpCache = null,
                        fetchViaProxy = null,
                    ),
                )
            }
        }.onSuccess { onCreated(AndroidCreatedNavigationItem.Feed(it.feedId)) }
            .onFailure { errorResource = AndroidFeedCreationPolicy.failureResource(it, isFeed = true) }
        working = false
    }

    fun discover() {
        val submitted = normalizedUrl ?: return
        working = true
        errorResource = null
        scope.launch {
            runCatching {
                coreRuntime.remoteForGeneration(sessionGeneration) { core ->
                    core.discoverSubscriptions(
                        DiscoverSubscriptionsRequest(
                            url = submitted,
                            username = null,
                            password = null,
                            userAgent = null,
                            fetchViaProxy = null,
                        ),
                    )
                }
            }.onSuccess { found ->
                when (found.size) {
                    0 -> errorResource = R.string.feed_discovery_empty
                    1 -> create(found.single().url)
                    else -> {
                        candidates = found
                        selectedCandidate = 0
                    }
                }
            }.onFailure { errorResource = AndroidFeedCreationPolicy.failureResource(it, isFeed = true) }
            working = false
        }
    }

    AlertDialog(
        onDismissRequest = { if (!working) onDismiss() },
        title = { Text(stringResource(if (candidates.isEmpty()) R.string.nav_add_feed else R.string.feed_choose)) },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth().heightIn(max = 460.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                if (candidates.isEmpty()) {
                    OutlinedTextField(
                        value = url,
                        onValueChange = { url = it; errorResource = null },
                        label = { Text(stringResource(R.string.feed_url_label)) },
                        placeholder = { Text(stringResource(R.string.feed_url_hint)) },
                        singleLine = true,
                        enabled = !working,
                        isError = url.isNotBlank() && normalizedUrl == null,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Text(
                        stringResource(R.string.feed_discovery_explanation),
                        style = MaterialTheme.typography.bodySmall,
                    )
                    Text(stringResource(R.string.feed_category), style = MaterialTheme.typography.labelLarge)
                    androidx.compose.foundation.layout.Box {
                        OutlinedButton(
                            onClick = { categoryMenuExpanded = true },
                            enabled = !working,
                        ) { Text(categoryLabel) }
                        DropdownMenu(
                            expanded = categoryMenuExpanded,
                            onDismissRequest = { categoryMenuExpanded = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.feed_default_category)) },
                                onClick = { categoryId = null; categoryMenuExpanded = false },
                            )
                            categories.forEach { category ->
                                DropdownMenuItem(
                                    text = { Text(category.title) },
                                    onClick = { categoryId = category.id; categoryMenuExpanded = false },
                                )
                            }
                        }
                    }
                } else {
                    candidates.forEachIndexed { index, candidate ->
                        Row(
                            modifier = Modifier.fillMaxWidth().clickable(enabled = !working) {
                                selectedCandidate = index
                            }.padding(vertical = 5.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(
                                selected = index == selectedCandidate,
                                enabled = !working,
                                onClick = { selectedCandidate = index },
                            )
                            Column {
                                Text(candidate.title.ifBlank { candidate.url })
                                Text(candidate.url, style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                }
                if (errorResource != null) Text(
                    stringResource(errorResource!!),
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                )
                if (working) CircularProgressIndicator()
            }
        },
        confirmButton = {
            TextButton(
                enabled = !working && (candidates.isNotEmpty() || normalizedUrl != null),
                onClick = {
                    if (candidates.isEmpty()) discover()
                    else scope.launch { create(candidates[selectedCandidate].url) }
                },
            ) { Text(stringResource(if (candidates.isEmpty()) R.string.action_continue else R.string.action_add)) }
        },
        dismissButton = {
            TextButton(enabled = !working, onClick = {
                if (candidates.isNotEmpty()) { candidates = emptyList(); errorResource = null }
                else onDismiss()
            }) { Text(stringResource(if (candidates.isEmpty()) R.string.action_cancel else R.string.action_back)) }
        },
    )
}

@Composable
internal fun AndroidAddCategoryDialog(
    coreRuntime: AndroidCoreRuntime,
    sessionGeneration: Long,
    categories: List<AndroidNavigationCategoryRef>,
    onDismiss: () -> Unit,
    onCreated: (AndroidCreatedNavigationItem) -> Unit,
) {
    val scope = rememberCoroutineScope()
    var title by remember { mutableStateOf("") }
    var working by remember { mutableStateOf(false) }
    var errorResource by remember { mutableStateOf<Int?>(null) }
    val normalized = AndroidFeedCreationPolicy.categoryTitle(title)
    val duplicate = normalized != null && AndroidFeedCreationPolicy.isDuplicateCategory(normalized, categories)

    AlertDialog(
        onDismissRequest = { if (!working) onDismiss() },
        title = { Text(stringResource(R.string.nav_add_category)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = title,
                    onValueChange = { title = it; errorResource = null },
                    label = { Text(stringResource(R.string.feed_category_name)) },
                    singleLine = true,
                    enabled = !working,
                    isError = duplicate,
                )
                if (duplicate) Text(
                    stringResource(R.string.feed_category_already_exists),
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                )
                if (errorResource != null) Text(
                    stringResource(errorResource!!),
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                )
                if (working) CircularProgressIndicator()
            }
        },
        confirmButton = {
            TextButton(
                enabled = !working && normalized != null && !duplicate,
                onClick = {
                    val submitted = normalized ?: return@TextButton
                    working = true
                    errorResource = null
                    scope.launch {
                        runCatching {
                            coreRuntime.remoteForGeneration(sessionGeneration) { core ->
                                core.createCategory(submitted)
                            }
                        }.onSuccess { onCreated(AndroidCreatedNavigationItem.Category(it.categoryId)) }
                            .onFailure { errorResource = AndroidFeedCreationPolicy.failureResource(it, isFeed = false) }
                        working = false
                    }
                },
            ) { Text(stringResource(R.string.action_add)) }
        },
        dismissButton = { TextButton(enabled = !working, onClick = onDismiss) { Text(stringResource(R.string.action_cancel)) } },
    )
}
