package de.circledev.fluxnews.nativeapp

import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import uniffi.flux_uniffi.ListeningListFeed
import uniffi.flux_uniffi.ListeningListItem
import uniffi.flux_uniffi.DownloadOrigin
import uniffi.flux_uniffi.FeedIconVariant
import uniffi.flux_uniffi.ListeningListSort
import uniffi.flux_uniffi.MediaArtworkSource

internal fun androidListeningListReloadIsCurrent(
    activeSessionGeneration: Long?,
    latestReloadGeneration: Long,
    expectedSessionGeneration: Long,
    expectedReloadGeneration: Long,
): Boolean =
    activeSessionGeneration == expectedSessionGeneration &&
        latestReloadGeneration == expectedReloadGeneration

internal sealed interface AndroidListeningListArtwork {
    data class RemoteUrl(val url: String) : AndroidListeningListArtwork
    data class LocalReference(val reference: String) : AndroidListeningListArtwork
}

internal data class AndroidListeningListState(
    val items: List<ListeningListItem> = emptyList(),
    val feeds: List<ListeningListFeed> = emptyList(),
    val selectedFeedId: Long? = null,
    val sort: ListeningListSort = ListeningListSort.RECENTLY_ADDED,
    val feedIconVariant: FeedIconVariant = FeedIconVariant.NORMAL,
    val feedIconPngByFeedId: Map<Long, ByteArray> = emptyMap(),
    val artworkByEnclosureId: Map<Long, AndroidListeningListArtwork> = emptyMap(),
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
)

internal class AndroidListeningListStore(
    private val coreRuntime: AndroidCoreRuntime,
    private val transferCoordinator: AndroidMediaTransferCoordinator? = null,
) {
    private val mutationMutex = Mutex()
    private val feedIconMutex = Mutex()
    private val feedIconCache = mutableMapOf<FeedIconVariant, MutableMap<Long, ByteArray>>()
    private val unavailableFeedIcons = mutableMapOf<FeedIconVariant, MutableSet<Long>>()
    private val mutableState = kotlinx.coroutines.flow.MutableStateFlow(AndroidListeningListState())
    val state: kotlinx.coroutines.flow.StateFlow<AndroidListeningListState> = mutableState

    @Volatile
    private var sessionGeneration: Long? = null

    private val nextReloadGeneration = AtomicLong(0)

    fun activateSession(generation: Long?) {
        if (sessionGeneration == generation) return
        sessionGeneration = generation
        nextReloadGeneration.incrementAndGet()
        feedIconCache.clear()
        unavailableFeedIcons.clear()
        mutableState.value = AndroidListeningListState()
    }

    suspend fun reload() {
        val generation = sessionGeneration ?: return
        val reloadGeneration = nextReloadGeneration.incrementAndGet()
        val requested = mutableState.value
        mutableState.value = requested.copy(isLoading = true, errorMessage = null)

        val result = runCatching {
            coreRuntime.localForGeneration(generation) { core ->
                val feeds = core.listeningListFeeds()
                val selectedFeedId = requested.selectedFeedId
                    ?.takeIf { candidate -> feeds.any { it.feedId == candidate } }
                val items = core.listeningList(
                    feedId = selectedFeedId,
                    sort = requested.sort,
                )
                val artworkByEnclosureId = buildMap {
                    items
                        .flatMap { it.audioEnclosures }
                        .map { it.enclosure.id }
                        .distinct()
                        .forEach { enclosureId ->
                            when (val source = core.mediaArtworkSource(enclosureId = enclosureId)) {
                                is MediaArtworkSource.LocalReference -> {
                                    put(
                                        enclosureId,
                                        AndroidListeningListArtwork.LocalReference(source.reference),
                                    )
                                }
                                is MediaArtworkSource.RemoteUrl -> {
                                    put(enclosureId, AndroidListeningListArtwork.RemoteUrl(source.url))
                                }
                                null -> Unit
                            }
                        }
                }
                Quadruple(feeds, selectedFeedId, items, artworkByEnclosureId)
            }
        }

        if (
            !androidListeningListReloadIsCurrent(
                sessionGeneration,
                nextReloadGeneration.get(),
                generation,
                reloadGeneration,
            )
        ) return
        result.fold(
            onSuccess = { (feeds, selectedFeedId, items, artworkByEnclosureId) ->
                if (
                    !androidListeningListReloadIsCurrent(
                        sessionGeneration,
                        nextReloadGeneration.get(),
                        generation,
                        reloadGeneration,
                    )
                ) return@fold
                mutableState.value = mutableState.value.copy(
                    items = items,
                    feeds = feeds,
                    selectedFeedId = selectedFeedId,
                    artworkByEnclosureId = artworkByEnclosureId,
                    isLoading = false,
                    errorMessage = null,
                )
            },
            onFailure = {
                if (
                    !androidListeningListReloadIsCurrent(
                        sessionGeneration,
                        nextReloadGeneration.get(),
                        generation,
                        reloadGeneration,
                    )
                ) return@fold
                mutableState.value = mutableState.value.copy(
                    isLoading = false,
                    errorMessage = "Listening List could not be loaded.",
                )
            },
        )
    }

    suspend fun setFeedId(feedId: Long?) {
        if (mutableState.value.selectedFeedId == feedId) return
        mutableState.value = mutableState.value.copy(selectedFeedId = feedId)
        reload()
    }

    suspend fun ensureFeedIcons(feedIds: List<Long>, variant: FeedIconVariant) {
        val generation = sessionGeneration ?: return
        feedIconMutex.withLock {
            if (sessionGeneration != generation) return@withLock

            val cache = feedIconCache.getOrPut(variant) { mutableMapOf() }
            val unavailable = unavailableFeedIcons.getOrPut(variant) { mutableSetOf() }
            val requested = feedIds.asSequence()
                .filter { it > 0L }
                .distinct()
                .filter { it !in cache && it !in unavailable }
                .toList()

            if (requested.isNotEmpty()) {
                val loaded = runCatching {
                    coreRuntime.remoteForGeneration(generation) { core ->
                        requested.mapNotNull { feedId ->
                            core.feedIcon(feedId = feedId, variant = variant)
                                ?.pngData
                                ?.let { feedId to it }
                        }.toMap()
                    }
                }.getOrNull() ?: emptyMap()

                if (sessionGeneration != generation) return@withLock
                cache.putAll(loaded)
                unavailable.addAll(requested.filterNot(loaded::containsKey))
            }

            if (sessionGeneration == generation) {
                mutableState.value = mutableState.value.copy(
                    feedIconVariant = variant,
                    feedIconPngByFeedId = cache.toMap(),
                )
            }
        }
    }

    suspend fun setSort(sort: ListeningListSort) {
        if (mutableState.value.sort == sort) return
        mutableState.value = mutableState.value.copy(sort = sort)
        reload()
    }

    suspend fun removeFromListeningList(articleId: Long): Result<Unit> =
        mutate(reconcileTransfers = true) { core ->
            core.removeFromListeningList(articleId = articleId)
        }

    suspend fun requestDownload(enclosureId: Long): Result<Unit> =
        mutate(reconcileTransfers = true) { core ->
            core.requestDownload(enclosureId = enclosureId, origin = DownloadOrigin.MANUAL)
        }

    suspend fun cancelDownload(enclosureId: Long): Result<Unit> =
        mutate(reconcileTransfers = true) { core ->
            core.cancelDownload(enclosureId = enclosureId)
        }

    suspend fun retryDownload(enclosureId: Long): Result<Unit> =
        mutate(reconcileTransfers = true) { core ->
            core.retryDownload(enclosureId = enclosureId)
        }

    suspend fun deleteDownload(enclosureId: Long): Result<Unit> =
        mutate(reconcileTransfers = true) { core ->
            core.requestDownloadDeletion(enclosureId = enclosureId)
        }

    private suspend fun mutate(
        reconcileTransfers: Boolean = false,
        operation: (uniffi.flux_uniffi.Flux) -> Unit,
    ): Result<Unit> = mutationMutex.withLock {
        val generation = sessionGeneration ?: return@withLock Result.failure(
            IllegalStateException("No active Core session."),
        )
        val result = runCatching {
            coreRuntime.localForGeneration(generation) { core -> operation(core) }
        }
        if (result.isSuccess && sessionGeneration == generation) {
            if (reconcileTransfers) {
                transferCoordinator?.reconcileAndSignal(generation)
            }
            reload()
        }
        result
    }
}


private data class Quadruple<A, B, C, D>(
    val first: A,
    val second: B,
    val third: C,
    val fourth: D,
)
