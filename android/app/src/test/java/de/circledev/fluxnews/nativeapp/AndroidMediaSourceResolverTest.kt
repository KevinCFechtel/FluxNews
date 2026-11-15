package de.circledev.fluxnews.nativeapp

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.flux_uniffi.Enclosure
import uniffi.flux_uniffi.MediaKind
import uniffi.flux_uniffi.PlaybackPreparation
import uniffi.flux_uniffi.PlaybackState
import uniffi.flux_uniffi.PlaybackStatus

class AndroidMediaSourceResolverTest {
    @Test
    fun readableLocalReferenceWinsOverRemoteSource() = withMediaRoot { root ->
        val downloaded = File(root, "downloads/42.mp3")
        checkNotNull(downloaded.parentFile).let { parent ->
            check(parent.mkdirs() || parent.isDirectory)
        }
        downloaded.writeText("audio")

        val resolved = AndroidMediaSourceResolver(root).resolve(
            preparation(localFile = "downloads/42.mp3"),
        )

        assertTrue(resolved is AndroidResolvedPlaybackSource.Local)
        assertEquals(downloaded.canonicalFile, (resolved as AndroidResolvedPlaybackSource.Local).file)
    }

    @Test
    fun missingLocalReferenceFallsBackToRemoteSource() = withMediaRoot { root ->
        val resolved = AndroidMediaSourceResolver(root).resolve(
            preparation(localFile = "downloads/missing.mp3"),
        )

        assertEquals(
            AndroidResolvedPlaybackSource.Remote("https://media.example/episode.mp3"),
            resolved,
        )
    }

    @Test
    fun pathTraversalCannotEscapeMediaRoot() = withMediaRoot { root ->
        val escaped = File(root.parentFile, "escaped.mp3")
        escaped.writeText("audio")

        val resolved = AndroidMediaSourceResolver(root).resolve(
            preparation(localFile = "../escaped.mp3"),
        )

        assertEquals(
            AndroidResolvedPlaybackSource.Remote("https://media.example/episode.mp3"),
            resolved,
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun invalidRemoteSchemeIsRejected() = withMediaRoot { root ->
        AndroidMediaSourceResolver(root).resolve(
            preparation(localFile = null, remoteUrl = "file:///tmp/episode.mp3"),
        )
    }

    private fun preparation(
        localFile: String?,
        remoteUrl: String = "https://media.example/episode.mp3",
    ) = PlaybackPreparation(
        enclosure = Enclosure(
            id = 42L,
            articleId = 7L,
            url = remoteUrl,
            mimeType = "audio/mpeg",
            sizeBytes = null,
            remoteMediaProgressionSeconds = 0uL,
            mediaKind = MediaKind.AUDIO,
        ),
        articleTitle = "Episode",
        feedTitle = "Feed",
        playbackState = PlaybackState(
            enclosureId = 42L,
            positionMs = 0uL,
            durationMs = null,
            status = PlaybackStatus.NOT_STARTED,
            updatedAt = null,
        ),
        localFile = localFile,
        durationMs = null,
        artworkSource = null,
    )

    private fun withMediaRoot(block: (File) -> Unit) {
        val root = Files.createTempDirectory("flux-media-root").toFile()
        try {
            block(root)
        } finally {
            root.parentFile?.resolve("escaped.mp3")?.delete()
            root.deleteRecursively()
        }
    }
}
