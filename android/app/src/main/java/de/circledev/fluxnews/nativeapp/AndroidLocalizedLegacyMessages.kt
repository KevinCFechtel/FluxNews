package de.circledev.fluxnews.nativeapp

import android.content.Context

/** Translate store messages at the presentation boundary without injecting Context into background jobs. */
internal fun Context.localizedLegacyUiMessage(message: String): String = when (message) {
    "Article could not be marked as read." -> getString(R.string.audit_search_read)
    "Article could not be marked as unread." -> getString(R.string.audit_search_unread)
    "Article could not be starred." -> getString(R.string.audit_search_star)
    "Article could not be unstarred." -> getString(R.string.audit_search_unstar)
    "Saved to third-party service." -> getString(R.string.audit_search_saved)
    "Article could not be saved to the third-party service." -> getString(R.string.audit_search_save_fail)
    "Added to Listening List." -> getString(R.string.l10n_added_list)
    "Removed from Listening List." -> getString(R.string.l10n_removed_list)
    "Listening List could not be updated." -> getString(R.string.l10n_list_update_failed)
    "Download action could not be completed." -> getString(R.string.audit_download_fail)
    "Unread articles could not be loaded." -> getString(R.string.l10n_unread_load_failed)
    "Articles could not be marked as read." -> getString(R.string.l10n_mark_all_failed)
    "All unread articles in this scope were marked as read." -> getString(R.string.l10n_mark_all_done)
    "Articles could not be marked unread." -> getString(R.string.audit_timeline_unread_failed)
    "More articles could not be loaded." -> getString(R.string.audit_timeline_more_failed)
    "Articles could not be loaded." -> getString(R.string.audit_timeline_load_failed)
    "Listening List could not be loaded." -> getString(R.string.l10n_list_load_failed)
    "Playback completion could not be saved." -> getString(R.string.l10n_playback_save_failed)
    "Media playback failed." -> getString(R.string.l10n_playback_failed)
    "Search could not be completed." -> getString(R.string.search_failed)
    "More search results could not be loaded." -> getString(R.string.audit_search_more_load)
    "More results could not be loaded." -> getString(R.string.audit_search_more_load)
    "Sync failed. Showing locally stored data." -> getString(R.string.audit_sync_failed)
    "Configuration restore could not be recovered. Restart FluxNews before making further changes." -> getString(R.string.l10n_account_restore_recover_failed)
    "Wait for the local state rebuild to finish." -> getString(R.string.l10n_account_wait_rebuild)
    "Enter both a Miniflux server URL and API key." -> getString(R.string.l10n_account_enter_creds)
    "The existing account credentials could not be read." -> getString(R.string.l10n_account_existing_creds_error)
    "The account could not be activated. Your previous account is still active." -> getString(R.string.l10n_account_activate_failed)
    "The account could not be removed." -> getString(R.string.l10n_account_remove_failed)
    "Stored account credentials could not be read." -> getString(R.string.audit_startup_cred_error)
    "The previous FluxNews account could not be migrated yet. Retry or configure the account manually." -> getString(R.string.audit_startup_migration_error)
    "The stored account could not be started." -> getString(R.string.l10n_account_start_failed)
    "Enter a valid HTTP or HTTPS Miniflux server URL." -> getString(R.string.l10n_account_url_invalid)
    "The Miniflux server could not be reached. Check the server URL and network connection." -> getString(R.string.l10n_account_unreachable)
    "Miniflux rejected the API key." -> getString(R.string.l10n_account_bad_key)
    "This server does not provide the required Miniflux endpoint." -> getString(R.string.l10n_account_incompatible)
    "Custom headers must have unique valid names and cannot replace FluxNews transport headers." -> getString(R.string.l10n_account_headers_invalid)
    "The Miniflux server returned an unexpected response." -> getString(R.string.l10n_account_server_response)
    "The Miniflux account could not be validated." -> getString(R.string.l10n_account_validation_failed)
    "Selected startup feed or category is not in the current catalog" -> getString(R.string.l10n_migration_startup_missing)
    "Some legacy feeds are missing from the current catalog" -> getString(R.string.l10n_migration_feeds_missing)
    else -> message
}


/**
 * Migration releases persisted English counter fragments. Localize known counts only at the
 * display boundary; unknown legacy messages still use the existing fallback.
 */
private val legacyMigrationCounters = listOf(
    Regex("""^(\d+) missing audio attachment\(s\)$""") to R.plurals.l10n_migration_missing_audio,
    Regex("""^(\d+) file\(s\) could not be adopted$""") to R.plurals.l10n_migration_file_adoption_failed,
    Regex("""^(\d+) missing article\(s\)$""") to R.plurals.l10n_migration_missing_article,
    Regex("""^(\d+) ambiguous audio attachment\(s\)$""") to R.plurals.l10n_migration_ambiguous_audio,
    Regex("""^(\d+) old playback positions? discarded: no local download and no longer available on the server\.$""") to R.plurals.l10n_migration_discarded_playback,
)

internal fun legacyMigrationCounter(message: String): Pair<Int, Int>? =
    legacyMigrationCounters.firstNotNullOfOrNull { (pattern, resId) ->
        pattern.matchEntire(message)?.groupValues?.get(1)?.toIntOrNull()?.let { resId to it }
    }

internal fun Context.localizedLegacyMigrationStatus(status: String): String =
    status.split("; ").joinToString("; ") { fragment ->
        val text = fragment.trim()
        legacyMigrationCounter(text)?.let { (resId, count) ->
            resources.getQuantityString(resId, count, count)
        } ?: localizedLegacyUiMessage(text)
    }
