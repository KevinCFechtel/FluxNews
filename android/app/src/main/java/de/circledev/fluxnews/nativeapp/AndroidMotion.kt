package de.circledev.fluxnews.nativeapp

import androidx.compose.animation.ContentTransform
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween

/**
 * One motion vocabulary for Android navigation and overlays.
 *
 * Large lateral movement is reserved for the Material navigation drawer. Top-level destinations
 * primarily fade, while true drill-down content uses only a small directional offset.
 */
internal object AndroidMotion {
    const val ReaderDurationMillis = 220

    private const val TopLevelDurationMillis = 180
    private const val DrillDownDurationMillis = 220
    private const val ScrimDurationMillis = 180
    private const val DrillDownOffsetDivisor = 16
    private const val ReaderVerticalOffsetDivisor = 20

    fun topLevelEnter(): EnterTransition =
        fadeIn(animationSpec = tween(TopLevelDurationMillis, easing = FastOutSlowInEasing))

    fun topLevelExit(): ExitTransition =
        fadeOut(animationSpec = tween(TopLevelDurationMillis, easing = FastOutSlowInEasing))

    fun settingsForward(): ContentTransform =
        (
            slideInHorizontally(
                animationSpec = tween(DrillDownDurationMillis, easing = FastOutSlowInEasing),
                initialOffsetX = { it / DrillDownOffsetDivisor },
            ) + fadeIn(
                animationSpec = tween(DrillDownDurationMillis, easing = FastOutSlowInEasing),
            )
        ).togetherWith(
            slideOutHorizontally(
                animationSpec = tween(DrillDownDurationMillis, easing = FastOutSlowInEasing),
                targetOffsetX = { -it / DrillDownOffsetDivisor },
            ) + fadeOut(
                animationSpec = tween(DrillDownDurationMillis, easing = FastOutSlowInEasing),
            ),
        )

    fun settingsBack(): ContentTransform =
        (
            slideInHorizontally(
                animationSpec = tween(DrillDownDurationMillis, easing = FastOutSlowInEasing),
                initialOffsetX = { -it / DrillDownOffsetDivisor },
            ) + fadeIn(
                animationSpec = tween(DrillDownDurationMillis, easing = FastOutSlowInEasing),
            )
        ).togetherWith(
            slideOutHorizontally(
                animationSpec = tween(DrillDownDurationMillis, easing = FastOutSlowInEasing),
                targetOffsetX = { it / DrillDownOffsetDivisor },
            ) + fadeOut(
                animationSpec = tween(DrillDownDurationMillis, easing = FastOutSlowInEasing),
            ),
        )

    fun detailCrossfade(): ContentTransform =
        fadeIn(
            animationSpec = tween(TopLevelDurationMillis, easing = FastOutSlowInEasing),
        ).togetherWith(
            fadeOut(
                animationSpec = tween(TopLevelDurationMillis, easing = FastOutSlowInEasing),
            ),
        )

    fun readerScrimEnter(): EnterTransition =
        fadeIn(animationSpec = tween(ScrimDurationMillis, easing = FastOutSlowInEasing))

    fun readerScrimExit(): ExitTransition =
        fadeOut(animationSpec = tween(ScrimDurationMillis, easing = FastOutSlowInEasing))

    fun readerSurfaceEnter(compactPortrait: Boolean): EnterTransition {
        val fade = fadeIn(
            animationSpec = tween(ReaderDurationMillis, easing = FastOutSlowInEasing),
        )
        return if (compactPortrait) {
            slideInVertically(
                animationSpec = tween(ReaderDurationMillis, easing = FastOutSlowInEasing),
                initialOffsetY = { it / ReaderVerticalOffsetDivisor },
            ) + fade
        } else {
            scaleIn(
                animationSpec = tween(ReaderDurationMillis, easing = FastOutSlowInEasing),
                initialScale = 0.985f,
            ) + fade
        }
    }

    fun readerSurfaceExit(compactPortrait: Boolean): ExitTransition {
        val fade = fadeOut(
            animationSpec = tween(ReaderDurationMillis, easing = FastOutSlowInEasing),
        )
        return if (compactPortrait) {
            slideOutVertically(
                animationSpec = tween(ReaderDurationMillis, easing = FastOutSlowInEasing),
                targetOffsetY = { it / ReaderVerticalOffsetDivisor },
            ) + fade
        } else {
            scaleOut(
                animationSpec = tween(ReaderDurationMillis, easing = FastOutSlowInEasing),
                targetScale = 0.985f,
            ) + fade
        }
    }
}
