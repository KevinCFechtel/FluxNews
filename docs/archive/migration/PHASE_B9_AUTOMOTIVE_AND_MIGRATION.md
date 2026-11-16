# Phase B9 Automotive and Legacy Migration

## Legacy source

The inventory below is based on `KevinCFechtel/FluxNews` `main` at commit
`481eb08` (`update depenedencies`). It is source evidence only; the new Core
schema and ownership rules in `PHASE_B_MEDIA_CORE.md` remain authoritative.

## Proven legacy persistence

The legacy SQLite database is `news_database.db`, schema version 12. Its media
tables are:

```text
news(newsID, feedID, title, ..., publishedAt, ...)
feeds(feedID, title, ...)
categories(categoryID, title)
attachments(attachmentID, newsID, attachmentURL, attachmentMimeType,
            mediaProgression)
```

`attachments.attachmentID` is the Miniflux attachment identity and
`attachments.newsID` is the article relationship. Audio is selected from the
attachment MIME type. The implementation permits multiple attachments, so a
legacy article-keyed playback value is imported only when exactly one audio
attachment resolves for that article.

Playback progress uses `AudioProgressStore`:

- SharedPreferences key: `audio_progress_<newsID>`.
- Value: decimal milliseconds stored as a string.
- Keychain fallback uses the same key through `flutter_secure_storage`.
- A stored `0` is explicit reset/completion state; absent is different from
  zero and permits the server position to be used.
- The legacy player may upload progress in whole seconds to Miniflux.

Download metadata uses Keychain, not SQLite:

- `audio_download_path_<attachmentID>` and URL fallback key
  `audio_download_path_url_<base64UrlEncodedURL>`.
- `audio_download_ts_<attachmentID>` stores the download timestamp.
- `audio_download_skipped_<attachmentID>` stores the literal `true` for user
  suppression.
- `flux_download_title_<attachmentID>` and
  `flux_download_feed_title_<attachmentID>` store automotive display metadata.
- Files are scanned from `getApplicationSupportDirectory()/audio_cache`.
- The filename convention is `audio_<attachmentID>_<millisecondsSinceEpoch>`
  followed by the source URL extension. The file name is not the identity.

Podcast settings are stored in Keychain:

- `autoDownloadAudioAfterSync`
- `downloadAudioOnlyOnWifi`
- `deleteAudioAfterPlayback`
- `audioDownloadRetentionDays`
- `openAudioItemsInPlayer`

The source also stores transient/background and debug state in Keychain, but
those values are not media-domain state and are not imported into Core.

## Automotive behavior

The legacy CarPlay service enumerates downloaded files, uses cached attachment
title/feed metadata, and starts playback with the attachment ID and article ID
in extras. Its item identity is the file URI. Android Auto is provided through
the audio-service media browser and uses the same downloaded-file catalog.
These are presentation/runtime caches, not durable domain entities, and are
therefore rebuilt from Core read models by native clients.

## Migration boundary

The source is sufficient to define the mappings and safe rejection rules. A
native importer still needs access to the platform-owned Keychain,
SharedPreferences, and application-support files. No such iOS or Android
client exists in this repository, and macOS cannot access another platform's
app sandbox. Accordingly:

- article/enclosure identity and the exact database schema are migration-ready;
- playback is importable only for one resolvable audio enclosure per article;
- ambiguous articles are skipped and reported, never guessed;
- downloaded-file import requires a native platform adapter to verify the file,
  resolve its attachment, and call the Core download finalization operation;
- legacy settings map to Core policies only after explicit account/install
  association; UI-only and runtime-only settings are dropped;
- legacy data is never deleted by the migration.

Core migration semantics deliberately adapt this legacy behavior rather than
copying its implicit completion convention:

- explicit legacy zero does not become `Completed`;
- explicit legacy zero does not become resumable `InProgress` and is excluded
  from `continue_listening()`;
- positive legacy progress may become `InProgress` and queues normal Core media
  progression delivery;
- a legacy source without a historical timestamp is retained with Core's
  explicit oldest-sortable migration timestamp, never the import time, so it
  cannot falsely outrank known playback in Continue Listening;
- zero does not queue remote progression or overwrite existing Core playback;
- existing playback state wins, and repeated imports are harmless;
- `import_legacy_playback()` does not write a global completion marker, including
  for empty or partial batches;
- the future native platform migration coordinator owns final completion because
  only it can know whether Keychain, SharedPreferences, files, and other legacy
  sources were fully evaluated. No explicit completion API is currently needed.

The unresolved case is platform extraction and verification of Keychain,
SharedPreferences, and files. It does not block Core automotive browsing or
Continue Listening, which use the current Core models directly.
