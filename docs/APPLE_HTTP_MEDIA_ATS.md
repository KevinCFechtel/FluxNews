# Apple HTTP Media and App Transport Security (A1)

**Decision (2026-10-11):** The native iOS/iPadOS and macOS **host applications** explicitly allow insecure HTTP loads through `NSAppTransportSecurity -> NSAllowsArbitraryLoads = YES`. The widget extensions retain their default ATS policy.

## Why a broad host exception is necessary

Flux displays content from arbitrary RSS subscriptions configured on a user's Miniflux installation. Its media hosts are not known in advance and are not restricted to the Miniflux server hostname.

| Operation | Native API | HTTP URLs |
| --- | --- | --- |
| Article images | iOS `ArticleImagePipeline` / `URLSession` | Allowed by host ATS exception |
| Podcast artwork | iOS/macOS `URLSession` | Allowed by host ATS exception |
| Podcast downloads | iOS background `URLSession`, macOS `URLSessionDownloadTask` | Allowed by host ATS exception |
| Remote podcast playback | iOS/macOS `AVPlayerItem(url:)` | Allowed by host ATS exception |

`NSAllowsArbitraryLoadsForMedia` only targets AVFoundation media loading and **does not allow the URLSession image, artwork, or download requests**. `NSExceptionDomains` cannot enumerate a user-defined, changing universe of media hostnames. Therefore the host apps require the broader exception to support arbitrary HTTP-only feed media. Do **not** mistakenly narrow the configuration to the media-only flag without redesigning the relevant URLSession network paths.

## Security and account separation

- HTTPS remains the preferred and expected scheme. HTTP feed media is unauthenticated and unencrypted in transit; its bytes, request URLs and listening behavior can be observed or modified by parties on the network.
- **Important:** ATS is a process/bundle-wide policy. This exception also permits HTTP requests made to a manually configured HTTP Miniflux account server; ATS cannot confine the exception to just RSS media domains. The existing separate HTTP-server warning and account validation semantics must remain intact. Do not describe the exception as restricted to media traffic or claim it protects credentials sent over HTTP.
- The Rust Miniflux HTTP client is not itself an Apple `URLSession` client and has its own transport/TLS configuration. This plist change does not implement or strengthen TLS in the Rust core.
- The widget extensions are left unchanged and do not download arbitrary feed images or podcasts.
- Redirects to HTTP are covered for the native host URLSession requests, but each real redirect/download case still needs device verification.

## App Store review explanation

> Flux is a user-configured RSS and podcast reader. Its users subscribe to arbitrary publishers through Miniflux. Some independent publishers still publish podcast enclosures, episode artwork, and article images only via plain HTTP. The host application loads these user-selected third-party URLs using both URLSession (images, artwork, background downloads) and AVFoundation (streaming). The app cannot supply a predetermined finite list of publisher domains, and the media-only ATS exception would not cover URLSession requests. We therefore require NSAllowsArbitraryLoads for the host apps. HTTPS is used wherever publishers support it, and the app distinguishes and warns about unencrypted HTTP account servers. Widget extensions retain default ATS.

## Validation and limitations

Automated structural tests in the existing iOS and macOS XCTest targets parse the **source host and widget Info.plists**, assert the declared host exception, and check that widget ATS remains unchanged. The existing Apple CI exercises the clients and tests but cannot by itself establish HTTP success from arbitrary publishers.

**Outstanding real-environment acceptance** (record pass/fail and sample URL for each target separately):

1. HTTPS article thumbnail and podcast artwork.
2. HTTP-only article image in the native timeline.
3. HTTP-only podcast enclosure in `AVPlayer`, including pause/seek and background playback.
4. HTTP-only podcast download in an iOS background URLSession and the macOS download path.
5. HTTP-only remote artwork requested using `URLSession`.
6. HTTPS URL redirecting to HTTP media (and optionally HTTP redirecting to HTTPS), including response errors.
7. A configured HTTPS Miniflux account still works; a manually configured HTTP Miniflux account continues to show the existing warning.
8. Inspect **the built host apps'** Info.plists to confirm `NSAppTransportSecurity:NSAllowsArbitraryLoads = YES` and inspect widget Info.plists to confirm no additional exception.

**Status:** ATS plist policy and structural tests implemented. End-to-end network acceptance and App Store review acceptance **not yet independently verified**. A1 is not fully closed until the platform/device checks are recorded.
