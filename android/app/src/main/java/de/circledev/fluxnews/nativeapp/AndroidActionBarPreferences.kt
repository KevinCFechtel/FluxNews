package de.circledev.fluxnews.nativeapp

import androidx.compose.runtime.staticCompositionLocalOf
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

internal val LocalAndroidActionBarPreferences = staticCompositionLocalOf<AndroidActionBarPreferences> {
    error("AndroidActionBarPreferences was not provided")
}

/**
 * Android counterpart of the iOS configurable article-list action contract.
 * Sync is fixed at the beginning and More remains the overflow fallback; only
 * these actions participate in the persisted display-priority list.
 */
internal enum class AndroidActionBarAction(
    val storedValue: String,
    val displayName: String,
) {
    FilterAndSort("filterAndSort", "Filter and Sort"),
    ToggleReadFilter("toggleReadFilter", "All / Unread"),
    ToggleSortOrder("toggleSortOrder", "Sort Order"),
    Search("search", "Search"),
    MarkAllRead("markAllRead", "Mark All as Read"),
    MarkAllReadAndNext("markAllReadAndNext", "Mark All as Read and Continue"),
    ListeningList("listeningList", "Listening List"),
    Settings("settings", "Settings"),
    ;

    companion object {
        val defaultConfiguredActions = listOf(FilterAndSort)

        fun fromStoredValue(value: String): AndroidActionBarAction? =
            entries.firstOrNull { it.storedValue == value }
    }
}

internal data class AndroidActionBarPreferenceState(
    val actions: List<AndroidActionBarAction> = AndroidActionBarAction.defaultConfiguredActions,
)

internal data class AndroidArticleListResolvedActions(
    val direct: List<AndroidActionBarAction>,
    val overflow: List<AndroidActionBarAction>,
)

/**
 * Resolves persisted semantic Article List priorities into the controls a concrete Android
 * presentation may expose directly and through its always-reachable overflow.
 *
 * Availability is contextual presentation state only. It never rewrites the stored action order.
 */
internal object AndroidArticleListActionPolicy {
    fun isAvailable(
        action: AndroidActionBarAction,
        scope: AndroidNewsScope,
        hasNextScope: Boolean,
    ): Boolean = when (action) {
        AndroidActionBarAction.FilterAndSort,
        AndroidActionBarAction.ToggleSortOrder,
        AndroidActionBarAction.Search,
        AndroidActionBarAction.ListeningList,
        AndroidActionBarAction.Settings,
        -> true

        AndroidActionBarAction.ToggleReadFilter -> scope != AndroidNewsScope.Starred

        AndroidActionBarAction.MarkAllRead -> when (scope) {
            AndroidNewsScope.All,
            is AndroidNewsScope.Category,
            is AndroidNewsScope.Feed,
            -> true
            AndroidNewsScope.Starred -> false
        }

        AndroidActionBarAction.MarkAllReadAndNext ->
            hasNextScope && (scope is AndroidNewsScope.Category || scope is AndroidNewsScope.Feed)
    }

    fun resolvedActions(
        configuredActions: List<AndroidActionBarAction>,
        directCapacity: Int,
        scope: AndroidNewsScope,
        hasNextScope: Boolean,
    ): AndroidArticleListResolvedActions {
        val configured = configuredActions.distinct()
        val availableConfigured = configured.filter {
            isAvailable(it, scope = scope, hasNextScope = hasNextScope)
        }
        val direct = availableConfigured.take(directCapacity.coerceAtLeast(0))
        val directSet = direct.toSet()
        val configuredSet = configured.toSet()

        val overflowSelected = availableConfigured.filterNot(directSet::contains)
        val overflowUnselected = AndroidActionBarAction.entries.filter {
            it !in configuredSet && isAvailable(it, scope = scope, hasNextScope = hasNextScope)
        }

        return AndroidArticleListResolvedActions(
            direct = direct,
            overflow = overflowSelected + overflowUnselected,
        )
    }
}

internal class AndroidActionBarPreferences(
    private val store: AndroidPreferenceStore,
) {
    private val actionsKey = AndroidPreferenceKey.string("article-list-action-ids")
    private val defaultStoredValue = encode(AndroidActionBarAction.defaultConfiguredActions)

    val state: Flow<AndroidActionBarPreferenceState> =
        store.observe(actionsKey, defaultStoredValue)
            .map { AndroidActionBarPreferenceState(decode(it)) }
            .distinctUntilChanged()

    suspend fun setActions(actions: List<AndroidActionBarAction>) {
        store.write(actionsKey, encode(normalized(actions)))
    }

    suspend fun add(action: AndroidActionBarAction, current: List<AndroidActionBarAction>) {
        setActions(current + action)
    }

    suspend fun remove(action: AndroidActionBarAction, current: List<AndroidActionBarAction>) {
        setActions(current.filterNot { it == action })
    }

    suspend fun moveUp(action: AndroidActionBarAction, current: List<AndroidActionBarAction>) {
        val index = current.indexOf(action)
        if (index <= 0) return
        val updated = current.toMutableList()
        updated[index] = updated[index - 1]
        updated[index - 1] = action
        setActions(updated)
    }

    suspend fun moveDown(action: AndroidActionBarAction, current: List<AndroidActionBarAction>) {
        val index = current.indexOf(action)
        if (index < 0 || index >= current.lastIndex) return
        val updated = current.toMutableList()
        updated[index] = updated[index + 1]
        updated[index + 1] = action
        setActions(updated)
    }

    suspend fun resetToDefault() {
        setActions(AndroidActionBarAction.defaultConfiguredActions)
    }

    private fun decode(value: String): List<AndroidActionBarAction> {
        if (value.isEmpty()) return emptyList()
        return normalized(value.split(',').mapNotNull(AndroidActionBarAction::fromStoredValue))
    }

    private fun encode(actions: List<AndroidActionBarAction>): String =
        normalized(actions).joinToString(",") { it.storedValue }

    private fun normalized(actions: List<AndroidActionBarAction>): List<AndroidActionBarAction> =
        actions.distinct()
}
