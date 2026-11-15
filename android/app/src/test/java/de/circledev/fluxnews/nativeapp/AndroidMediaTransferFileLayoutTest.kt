package de.circledev.fluxnews.nativeapp

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Test

class AndroidMediaTransferFileLayoutTest {
    @Test
    fun preservesKnownRemoteExtension() {
        assertEquals(
            "downloads/42.mp3",
            AndroidMediaTransferFileLayout.reference(
                enclosureId = 42L,
                url = "https://media.example/episode.mp3?token=ignored",
                mimeType = "audio/mpeg",
            ),
        )
    }

    @Test
    fun fallsBackToMimeTypeWhenUrlHasNoKnownExtension() {
        assertEquals(
            "downloads/7.m4a",
            AndroidMediaTransferFileLayout.reference(
                enclosureId = 7L,
                url = "https://media.example/stream?id=7",
                mimeType = "audio/mp4; charset=binary",
            ),
        )
    }

    @Test
    fun destinationStaysUnderMediaRoot() {
        val root = Files.createTempDirectory("flux-media-layout").toFile()
        try {
            assertEquals(
                File(root, "downloads/9.ogg").canonicalFile,
                AndroidMediaTransferFileLayout.destination(root, "downloads/9.ogg"),
            )
        } finally {
            root.deleteRecursively()
        }
    }

    @Test(expected = IllegalArgumentException::class)
    fun destinationRejectsPathTraversal() {
        val root = Files.createTempDirectory("flux-media-layout").toFile()
        try {
            AndroidMediaTransferFileLayout.destination(root, "../outside.mp3")
        } finally {
            root.deleteRecursively()
        }
    }
}
