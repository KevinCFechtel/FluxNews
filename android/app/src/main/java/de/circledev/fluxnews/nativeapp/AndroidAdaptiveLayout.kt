package de.circledev.fluxnews.nativeapp

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

internal val AndroidFormContentMaxWidth: Dp = 600.dp
internal val AndroidSecondaryContentMaxWidth: Dp = 720.dp
internal val AndroidSettingsDetailMaxWidth: Dp = 720.dp

/**
 * Keeps phone presentation edge-to-edge while giving larger Android windows a readable
 * content measure. The surrounding destination remains responsible for its own app bar,
 * background and insets.
 */
@Composable
internal fun AndroidCenteredContent(
    maxWidth: Dp,
    modifier: Modifier = Modifier,
    content: @Composable (Modifier) -> Unit,
) {
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.TopCenter,
    ) {
        content(
            Modifier
                .widthIn(max = maxWidth)
                .fillMaxWidth()
                .fillMaxHeight(),
        )
    }
}
