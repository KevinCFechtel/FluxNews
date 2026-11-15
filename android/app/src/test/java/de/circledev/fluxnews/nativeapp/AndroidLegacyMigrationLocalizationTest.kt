package de.circledev.fluxnews.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AndroidLegacyMigrationLocalizationTest {
    @Test fun persistedMigrationCountersResolveToLocalizedPluralResources() {
        val examples = listOf(
            Triple("1 missing audio attachment(s)", R.plurals.l10n_migration_missing_audio, 1),
            Triple("3 missing audio attachment(s)", R.plurals.l10n_migration_missing_audio, 3),
            Triple("2 file(s) could not be adopted", R.plurals.l10n_migration_file_adoption_failed, 2),
            Triple("1 missing article(s)", R.plurals.l10n_migration_missing_article, 1),
            Triple("5 ambiguous audio attachment(s)", R.plurals.l10n_migration_ambiguous_audio, 5),
            Triple("1 old playback position discarded: no local download and no longer available on the server.", R.plurals.l10n_migration_discarded_playback, 1),
            Triple("4 old playback positions discarded: no local download and no longer available on the server.", R.plurals.l10n_migration_discarded_playback, 4),
        )
        examples.forEach { (message, expectedResource, expectedCount) ->
            assertEquals(expectedResource to expectedCount, legacyMigrationCounter(message))
        }
    }

    @Test fun unknownPersistedStatusRemainsUnmapped() {
        assertNull(legacyMigrationCounter("Legacy item still pending"))
    }
}
