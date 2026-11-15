package de.circledev.fluxnews.nativeapp

import androidx.compose.runtime.staticCompositionLocalOf
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged

internal val LocalAndroidArticlePreferences = staticCompositionLocalOf<AndroidArticlePreferences> { error("AndroidArticlePreferences was not provided") }

enum class AndroidArticleOpenPreference(val storedValue: String, val displayName: String) { OriginalLink("original", "Original link"), Reader("reader", "Reader"); companion object { fun fromStoredValue(value: String) = entries.firstOrNull { it.storedValue == value } ?: OriginalLink } }
internal enum class AndroidArticlePresentationMode(val storedValue: String, val displayName: String) { Compact("compact", "Compact"), Visual("visual", "Visual"), VisualCompact("visualCompact", "Visual Compact"); companion object { fun fromStoredValue(value: String) = entries.firstOrNull { it.storedValue == value } ?: Visual } }
internal enum class AndroidArticlePreviewLines(val lineCount: Int, val displayName: String) { Compact(2, "2 lines"), Standard(3, "3 lines"), Extended(5, "5 lines"); companion object { fun fromStoredValue(value: Int) = entries.firstOrNull { it.lineCount == value } ?: Standard } }
internal enum class AndroidArticleSwipeSide { Leading, Trailing }
internal enum class AndroidArticleSwipeSlot { FullSwipe, Additional }
internal enum class AndroidArticleSwipeAction(val storedValue: String, val displayName: String) {
    ReadUnread("readUnread", "Read / Unread"), StarUnstar("starUnstar", "Star / Unstar"), OpenOriginal("openOriginal", "Open Original"), OpenMiniflux("openMiniflux", "Open in Miniflux"), Comments("comments", "Open Comments"), Share("share", "Share"), SaveToService("saveToService", "Save to Third-Party Service"), ListeningList("listeningList", "Listening List"), DownloadAudio("downloadAudio", "Download Audio");
    companion object { fun fromStoredValue(value: String?) = value?.let { stored -> entries.firstOrNull { it.storedValue == stored } } }
}

internal data class AndroidArticleSwipeConfiguration(val leading: List<AndroidArticleSwipeAction>, val trailing: List<AndroidArticleSwipeAction>) {
    companion object {
        val Default = AndroidArticleSwipeConfiguration(listOf(AndroidArticleSwipeAction.ReadUnread), listOf(AndroidArticleSwipeAction.StarUnstar))
        fun normalized(actions: List<AndroidArticleSwipeAction>) = actions.distinct().takeLast(2)
    }
    fun actions(side: AndroidArticleSwipeSide) = if (side == AndroidArticleSwipeSide.Leading) leading else trailing
    fun fullSwipeAction(side: AndroidArticleSwipeSide) = actions(side).lastOrNull()
    fun additionalAction(side: AndroidArticleSwipeSide) = actions(side).takeIf { it.size == 2 }?.firstOrNull()
    fun setting(action: AndroidArticleSwipeAction?, side: AndroidArticleSwipeSide, slot: AndroidArticleSwipeSlot): AndroidArticleSwipeConfiguration {
        val current = actions(side); val full = current.lastOrNull(); val additional = current.takeIf { it.size == 2 }?.firstOrNull()
        val updated = when (slot) {
            AndroidArticleSwipeSlot.FullSwipe -> when { action == null -> emptyList(); additional != null && additional != action -> listOf(additional, action); else -> listOf(action) }
            AndroidArticleSwipeSlot.Additional -> when { full == null -> emptyList(); action != null && action != full -> listOf(action, full); else -> listOf(full) }
        }
        return if (side == AndroidArticleSwipeSide.Leading) copy(leading = normalized(updated)) else copy(trailing = normalized(updated))
    }
}

internal data class AndroidArticlePreferenceState(
    val openArticle: AndroidArticleOpenPreference = AndroidArticleOpenPreference.OriginalLink,
    val presentationMode: AndroidArticlePresentationMode = AndroidArticlePresentationMode.Visual,
    val previewLines: AndroidArticlePreviewLines = AndroidArticlePreviewLines.Standard,
    val showArticleCount: Boolean = true,
    val showRelativePublicationTime: Boolean = false,
    val removeArticlesWhenRead: Boolean = false,
    val markReadOnScrollover: Boolean = true,
    val swipeConfiguration: AndroidArticleSwipeConfiguration = AndroidArticleSwipeConfiguration.Default,
)

internal class AndroidArticlePreferences(private val store: AndroidPreferenceStore) {
    private val openArticleKey = AndroidPreferenceKey.string("articles-open"); private val presentationModeKey = AndroidPreferenceKey.string("articles-presentation-mode"); private val previewLinesKey = AndroidPreferenceKey.int("articles-preview-lines"); private val showArticleCountKey = AndroidPreferenceKey.boolean("articles-show-count"); private val relativePublicationTimeKey = AndroidPreferenceKey.boolean("articles-relative-publication-time"); private val removeWhenReadKey = AndroidPreferenceKey.boolean("articles-remove-when-read"); private val scrolloverKey = AndroidPreferenceKey.boolean("articles-mark-read-on-scrollover")
    private val leadingFullKey = AndroidPreferenceKey.string("articles-swipe-leading-full"); private val leadingAdditionalKey = AndroidPreferenceKey.string("articles-swipe-leading-additional"); private val trailingFullKey = AndroidPreferenceKey.string("articles-swipe-trailing-full"); private val trailingAdditionalKey = AndroidPreferenceKey.string("articles-swipe-trailing-additional")

    private val baseState = combine(store.observe(openArticleKey, AndroidArticleOpenPreference.OriginalLink.storedValue), store.observe(presentationModeKey, AndroidArticlePresentationMode.Visual.storedValue), store.observe(previewLinesKey, AndroidArticlePreviewLines.Standard.lineCount), store.observe(showArticleCountKey, true), store.observe(relativePublicationTimeKey, false)) { open, mode, lines, count, relative -> BaseState(AndroidArticleOpenPreference.fromStoredValue(open), AndroidArticlePresentationMode.fromStoredValue(mode), AndroidArticlePreviewLines.fromStoredValue(lines), count, relative) }
    private val behaviorState = combine(store.observe(removeWhenReadKey, false), store.observe(scrolloverKey, true), swipeSideFlow(AndroidArticleSwipeSide.Leading), swipeSideFlow(AndroidArticleSwipeSide.Trailing)) { remove, scrollover, leading, trailing -> BehaviorState(remove, scrollover, leading, trailing) }
    val state: Flow<AndroidArticlePreferenceState> = combine(baseState, behaviorState) { base, behavior -> AndroidArticlePreferenceState(base.openArticle, base.presentationMode, base.previewLines, base.showArticleCount, base.relativePublicationTime, behavior.removeWhenRead, behavior.scrollover, AndroidArticleSwipeConfiguration(behavior.leading, behavior.trailing)) }.distinctUntilChanged()

    private fun swipeSideFlow(side: AndroidArticleSwipeSide): Flow<List<AndroidArticleSwipeAction>> {
        val fullKey = if (side == AndroidArticleSwipeSide.Leading) leadingFullKey else trailingFullKey; val additionalKey = if (side == AndroidArticleSwipeSide.Leading) leadingAdditionalKey else trailingAdditionalKey; val defaultFull = AndroidArticleSwipeConfiguration.Default.fullSwipeAction(side)!!.storedValue
        return combine(store.observe(fullKey, defaultFull), store.observe(additionalKey, "")) { fullValue, additionalValue -> AndroidArticleSwipeConfiguration.normalized(listOfNotNull(AndroidArticleSwipeAction.fromStoredValue(additionalValue), AndroidArticleSwipeAction.fromStoredValue(fullValue))) }
    }

    suspend fun setOpenArticle(value: AndroidArticleOpenPreference) = store.write(openArticleKey, value.storedValue)
    suspend fun setPresentationMode(value: AndroidArticlePresentationMode) = store.write(presentationModeKey, value.storedValue)
    suspend fun setPreviewLines(value: AndroidArticlePreviewLines) = store.write(previewLinesKey, value.lineCount)
    suspend fun setShowArticleCount(value: Boolean) = store.write(showArticleCountKey, value)
    suspend fun setShowRelativePublicationTime(value: Boolean) = store.write(relativePublicationTimeKey, value)
    suspend fun setRemoveArticlesWhenRead(value: Boolean) = store.write(removeWhenReadKey, value)
    suspend fun setMarkReadOnScrollover(value: Boolean) = store.write(scrolloverKey, value)
    suspend fun setSwipeAction(configuration: AndroidArticleSwipeConfiguration, action: AndroidArticleSwipeAction?, side: AndroidArticleSwipeSide, slot: AndroidArticleSwipeSlot) {
        val updated = configuration.setting(action, side, slot); val fullKey = if (side == AndroidArticleSwipeSide.Leading) leadingFullKey else trailingFullKey; val additionalKey = if (side == AndroidArticleSwipeSide.Leading) leadingAdditionalKey else trailingAdditionalKey
        store.write(fullKey, updated.fullSwipeAction(side)?.storedValue ?: ""); store.write(additionalKey, updated.additionalAction(side)?.storedValue ?: "")
    }
    private data class BaseState(val openArticle: AndroidArticleOpenPreference, val presentationMode: AndroidArticlePresentationMode, val previewLines: AndroidArticlePreviewLines, val showArticleCount: Boolean, val relativePublicationTime: Boolean)
    private data class BehaviorState(val removeWhenRead: Boolean, val scrollover: Boolean, val leading: List<AndroidArticleSwipeAction>, val trailing: List<AndroidArticleSwipeAction>)
}
