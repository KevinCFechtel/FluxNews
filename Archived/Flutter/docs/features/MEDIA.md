# Flux News Audio, Podcasts, and Media

Detailed context for playback progress, downloads, media controls, audio focus/session behavior, and the deferred Android Auto investigation.

## Podcast Progress And Download Overview

- Podcast playback positions are stored in SharedPreferences through `AudioProgressStore`, not Secure Storage. Legacy Secure Storage/Keychain values migrate on first read and are deleted afterward; the explicit string value `"0"` remains a meaningful completed/reset marker.
- Download overview progress uses the greater valid local/server position. Synced Miniflux `mediaProgression` is available before the audio player is opened: the overview reads attachment progression and `AudioDownloadService.refreshMediaProgressionCacheFromSync()` refreshes the in-memory cache after sync.
- Clearing local data deletes the local news/category/feed/attachment tables, feed icons, all downloaded audio files, cached download artwork, and associated download metadata. Running and queued downloads are cancelled and awaited first so they cannot recreate files after the deletion. If the audio handler was already initialized, the settings action stops playback before deleting the files; it does not initialize the audio service solely for cleanup.
- The downloaded-item progress bar is shown only for a positive position and is calculated against the news duration (`readingTime`).

## Article Images And Media Controls

- Compact news cards/rows use `BoxFit.cover` with the shared `newsImageCropAlignment` from `lib/ui/news_image_dimensions.dart`. The crop focal line is 38.2% from the top (golden-section bias) rather than exact vertical center. Decode cache width is derived from logical display width times device pixel ratio and capped at 1200 pixels; this reduces memory without distorting the source aspect ratio.
- `FluxNewsAudioHandler` publishes rewind 30 seconds, play/pause, fast-forward 30 seconds, and stop through `audio_service`. `skipToPrevious()` and `skipToNext()` intentionally delegate to rewind/fast-forward for compatibility with clients that still send track-skip actions. The Android compact notification shows the first three actions; stop remains available in the expanded notification and supported media surfaces.
- Merely initializing the audio handler must not claim audio focus. `play()` activates the audio session, while `stop()` persists progress, stops the player, resets the active URL, publishes idle state, and ends the iOS Live Activity. The iOS ActivityKit view currently exposes play/pause and skip-forward intents; its in-process `NotificationCenter` bridge is not a reliable general process-boundary command channel, so do not assume additional Live Activity controls work after the Flutter process has been terminated.

## Deferred Android Auto AudioFocus Investigation

- User observed on Android Auto / VW infotainment that Flux News podcast playback could start without audible audio and without the car recognizing the current track. After switching to Apple Music, audio and track recognition worked; switching back to Flux News then showed the Flux News track, but Apple Music and the podcast could play simultaneously.
- Current assessment: this is more likely an Android Auto / AudioFocus / MediaSession issue than a Background Sync issue.
- Relevant code: `lib/functions/flux_news_audio_handler.dart`.
- Current audio configuration uses `AudioSessionConfiguration` with Android media usage/content type and `AndroidAudioFocusGainType.gain`.
- Implemented follow-up:
  - `AudioSession.interruptionEventStream` is handled centrally in `FluxNewsAudioHandler`;
  - `pause` and `unknown` interruptions pause playback and do not auto-resume;
  - `duck` interruptions reduce volume to 25% and restore the previous volume when ducking ends;
  - `AudioSession.becomingNoisyEventStream` pauses playback;
  - Android and iOS no longer call `AudioSession.setActive(true)` during AudioHandler initialization; focus/session activation is requested only during explicit `play()`, so merely opening Flux News does not interrupt Apple Music or another player;
  - Android `play()` retries `AudioSession.setActive(true)` once and verifies shortly after dispatch that playback left `idle`; failures are logged as warnings;
  - debug-mode logging now covers `play()`, `pause()`, `session.setActive(true)` failures, player state, interruption events, becoming-noisy events, and `loadMediaItem()` source setup.
- Remaining possible follow-up:
  - verify MediaSession updates are emitted immediately after `loadMediaItem()` and before/after `_player.play()`;
  - retest Android Auto after these changes to confirm Apple Music and Flux News cannot play simultaneously and that VW infotainment recognizes the current track reliably.
- iOS keeps `AVAudioSessionCategory.playback` with `AVAudioSessionRouteSharingPolicy.longFormAudio`; this is intentional for CarPlay routing and ownership of Lock Screen/Dynamic Island controls. Do not replace it with `mixWithOthers` merely to avoid interruption symptoms, because that previously demoted Flux News from the primary Now Playing owner.
