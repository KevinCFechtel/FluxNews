//! Miniflux HTTP adapter. It maps wire data into domain values and never persists it.

use std::collections::HashMap;
use std::io::Read;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use crate::domain::{
    Article, ArticleSummary, Category, CoreError, CreateCategoryResult, CreateFeedRequest,
    CreateFeedResult, DiscoverSubscriptionsRequest, DiscoveredSubscription, Enclosure, Feed,
    SaveToServiceResult, SearchArticlesRequest, SearchArticlesResult,
};
use crate::sync_cancellation::SyncCancellation;
use chrono::{DateTime, SecondsFormat};
use serde::Deserialize;

const PAGE_SIZE: i64 = 100;
const CONNECT_TIMEOUT: Duration = Duration::from_secs(6);
const READ_TIMEOUT: Duration = Duration::from_secs(80);
const WRITE_TIMEOUT: Duration = Duration::from_secs(30);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(120);
const MEDIA_PROBE_TIMEOUT: Duration = Duration::from_secs(15);
const MEDIA_PROBE_CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
const MEDIA_PROBE_READ_TIMEOUT: Duration = Duration::from_secs(10);
const MAX_CUSTOM_HEADERS: usize = 32;
const MAX_HEADER_NAME_BYTES: usize = 256;
const MAX_HEADER_VALUE_BYTES: usize = 8 * 1024;

/// Runtime-only transport configuration supplied by the native secure store.
#[derive(Clone, PartialEq, Eq)]
pub struct HttpHeader {
    pub name: String,
    pub value: String,
}

impl std::fmt::Debug for HttpHeader {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("HttpHeader")
            .field("name", &self.name)
            .field("value", &"<redacted>")
            .finish()
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AccountValidationResult {
    pub installation_base: String,
    pub version: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MinifluxCapability {
    MediaProgressSync,
    SavedMediaSync,
}

impl AccountValidationResult {
    /// Runtime-only capabilities derived from the validated server version.
    pub fn capabilities(&self) -> Vec<MinifluxCapability> {
        MinifluxCapability::all_supported_by(&self.version)
    }
}

impl MinifluxCapability {
    pub fn all_supported_by(version: &str) -> Vec<Self> {
        let mut capabilities = Vec::new();
        if Self::media_progress_sync_supported(version) {
            capabilities.push(Self::MediaProgressSync);
        }
        if Self::saved_media_sync_supported(version) {
            capabilities.push(Self::SavedMediaSync);
        }
        capabilities
    }

    fn media_progress_sync_supported(version: &str) -> bool {
        let mut components = version.trim().trim_start_matches('v').split('.');
        let Some(major) = components
            .next()
            .and_then(|value| value.parse::<u64>().ok())
        else {
            return false;
        };
        let Some(minor) = components
            .next()
            .and_then(|value| value.parse::<u64>().ok())
        else {
            return false;
        };
        (major, minor) >= (2, 2)
    }
    fn saved_media_sync_supported(version: &str) -> bool {
        let mut components = version.trim().trim_start_matches('v').split('.');
        let Some(major) = components
            .next()
            .and_then(|value| value.parse::<u64>().ok())
        else {
            return false;
        };
        let Some(minor) = components
            .next()
            .and_then(|value| value.parse::<u64>().ok())
        else {
            return false;
        };
        let Some(patch) = components
            .next()
            .and_then(|value| value.parse::<u64>().ok())
        else {
            return false;
        };
        (major, minor, patch) >= (2, 2, 16)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum AccountValidationError {
    InvalidUrl,
    UnsupportedUrlScheme,
    Network,
    Unauthorized,
    IncompatibleServer,
    InvalidResponse,
    ServerUnavailable,
    InvalidCustomHeader,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AccountValidationDiagnostic {
    pub category: String,
    pub detail: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AccountValidationAttempt {
    pub result: Option<AccountValidationResult>,
    pub error: Option<AccountValidationError>,
    pub diagnostic: Option<AccountValidationDiagnostic>,
}

impl std::fmt::Display for AccountValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let message = match self {
            Self::InvalidUrl => "Miniflux installation URL is invalid",
            Self::UnsupportedUrlScheme => "Miniflux installation URL must use HTTP(S)",
            Self::Network => "Miniflux server could not be reached",
            Self::Unauthorized => "Miniflux rejected credentials",
            Self::IncompatibleServer => "Miniflux version endpoint was not found",
            Self::InvalidResponse => "Miniflux version response is invalid",
            Self::ServerUnavailable => "Miniflux server is temporarily unavailable",
            Self::InvalidCustomHeader => "custom HTTP headers are invalid",
        };
        f.write_str(message)
    }
}

pub fn validate_custom_headers(headers: &[HttpHeader]) -> Result<(), AccountValidationError> {
    if headers.len() > MAX_CUSTOM_HEADERS {
        return Err(AccountValidationError::InvalidCustomHeader);
    }
    let mut names = std::collections::HashSet::with_capacity(headers.len());
    for header in headers {
        let name = header.name.as_bytes();
        let value = header.value.as_bytes();
        if name.is_empty()
            || name.len() > MAX_HEADER_NAME_BYTES
            || value.len() > MAX_HEADER_VALUE_BYTES
            || !name.iter().all(|byte| {
                byte.is_ascii_alphanumeric()
                    || matches!(
                        byte,
                        b'!' | b'#'
                            | b'$'
                            | b'%'
                            | b'&'
                            | b'\''
                            | b'*'
                            | b'+'
                            | b'-'
                            | b'.'
                            | b'^'
                            | b'_'
                            | b'`'
                            | b'|'
                            | b'~'
                    )
            })
            || value
                .iter()
                .any(|byte| *byte < 0x20 && *byte != b'\t' || *byte == 0x7f)
        {
            return Err(AccountValidationError::InvalidCustomHeader);
        }
        let normalized = header.name.to_ascii_lowercase();
        if matches!(
            normalized.as_str(),
            "accept"
                | "connection"
                | "content-length"
                | "content-type"
                | "host"
                | "proxy-authenticate"
                | "proxy-authorization"
                | "te"
                | "trailer"
                | "transfer-encoding"
                | "upgrade"
                | "user-agent"
                | "x-auth-token"
        ) || !names.insert(normalized)
        {
            return Err(AccountValidationError::InvalidCustomHeader);
        }
    }
    Ok(())
}

impl std::error::Error for AccountValidationError {}

#[derive(Clone, Debug)]
pub struct RemoteSnapshot {
    pub categories: Vec<Category>,
    pub feeds: Vec<Feed>,
    pub articles: Vec<Article>,
    pub enclosures: Vec<Enclosure>,
}

/// Bounded changed-entry projection used by lightweight Background/Resume Sync.
/// Feed/category catalog changes are deliberately outside this contract.
#[derive(Clone, Debug)]
pub struct RemoteDelta {
    pub articles: Vec<Article>,
    pub enclosures: Vec<Enclosure>,
    /// Greatest Miniflux changed_at observed, expressed as Unix seconds.
    pub cursor: i64,
}

pub struct RemoteImage {
    pub content_type: Option<String>,
    pub bytes: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RemoteFeedInfo {
    pub id: i64,
    pub title: String,
    pub feed_url: String,
    pub disabled: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RemoteSavedMediaMarker {
    pub entry_id: i64,
    pub external_id: String,
    pub status: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RemoteSavedMediaArticle {
    pub article: Article,
    pub enclosures: Vec<Enclosure>,
}

/// Parses a configured installation URL. Query strings, fragments, and userinfo are rejected
/// because they cannot identify a stable Miniflux installation base.
pub fn normalize_installation_base(input: &str) -> Result<String, AccountValidationError> {
    let mut url = url::Url::parse(input).map_err(|_| AccountValidationError::InvalidUrl)?;
    if !matches!(url.scheme(), "https" | "http") {
        return Err(AccountValidationError::UnsupportedUrlScheme);
    }
    if url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return Err(AccountValidationError::InvalidUrl);
    }

    let path = url.path().trim_end_matches('/').to_string();
    let installation_path = if path.rsplit('/').next() == Some("v1") {
        path.strip_suffix("/v1").unwrap_or(&path)
    } else {
        &path
    };
    url.set_path(installation_path);
    Ok(url.as_str().trim_end_matches('/').to_string())
}

pub fn miniflux_entry_url(installation_base: &str, article_id: i64) -> String {
    format!("{installation_base}/unread/entry/{article_id}")
}

pub trait RemoteSource: Send + Sync {
    fn fetch_initial_articles(&self) -> Result<RemoteSnapshot, CoreError>;
    fn fetch_initial_articles_cancellable(
        &self,
        cancellation: &SyncCancellation,
    ) -> Result<Option<RemoteSnapshot>, CoreError> {
        if cancellation.is_cancelled() {
            return Ok(None);
        }
        let result = self.fetch_initial_articles();
        if cancellation.is_cancelled() {
            return Ok(None);
        }
        result.map(Some)
    }
    fn fetch_changed_articles_cancellable(
        &self,
        changed_after: i64,
        cancellation: &SyncCancellation,
    ) -> Result<Option<RemoteDelta>, CoreError> {
        if cancellation.is_cancelled() {
            return Ok(None);
        }
        let snapshot = self.fetch_initial_articles_cancellable(cancellation)?;
        if cancellation.is_cancelled() {
            return Ok(None);
        }
        Ok(snapshot.map(|snapshot| RemoteDelta {
            articles: snapshot.articles,
            enclosures: snapshot.enclosures,
            cursor: changed_after.saturating_add(1),
        }))
    }
    /// Returns a server-derived changed_at high-water mark for establishing a
    /// post-Full-Sync delta baseline. Test/embedded sources without changed_at
    /// support safely use zero; real Miniflux sources override this.
    fn delta_watermark_cancellable(
        &self,
        cancellation: &SyncCancellation,
    ) -> Result<Option<i64>, CoreError> {
        if cancellation.is_cancelled() {
            Ok(None)
        } else {
            Ok(Some(0))
        }
    }
    fn set_read_state(&self, article_ids: &[i64], read: bool) -> Result<(), CoreError>;
    fn set_starred_state(&self, article_id: i64, starred: bool) -> Result<(), CoreError>;
    fn set_starred_state_cancellable(
        &self,
        article_id: i64,
        starred: bool,
        cancellation: &SyncCancellation,
    ) -> Result<bool, CoreError> {
        if cancellation.is_cancelled() {
            return Ok(false);
        }
        let result = self.set_starred_state(article_id, starred);
        if cancellation.is_cancelled() {
            return Ok(false);
        }
        result.map(|()| true)
    }
    fn set_media_progression(&self, _enclosure_id: i64, _seconds: u64) -> Result<(), CoreError> {
        Err(CoreError::data("media progression updates are unavailable"))
    }
    fn search_articles(
        &self,
        _request: SearchArticlesRequest,
    ) -> Result<SearchArticlesResult, CoreError> {
        Err(CoreError::data("article search is unavailable"))
    }
    fn save_to_service(&self, _article_id: i64) -> Result<SaveToServiceResult, CoreError> {
        Err(CoreError::data("save-to-service is unavailable"))
    }
    fn discover_subscriptions(
        &self,
        _request: DiscoverSubscriptionsRequest,
    ) -> Result<Vec<DiscoveredSubscription>, CoreError> {
        Err(CoreError::data("feed discovery is unavailable"))
    }
    fn create_feed(&self, _request: CreateFeedRequest) -> Result<CreateFeedResult, CoreError> {
        Err(CoreError::data("feed creation is unavailable"))
    }
    fn create_category(&self, _title: String) -> Result<CreateCategoryResult, CoreError> {
        Err(CoreError::data("category creation is unavailable"))
    }
    fn fetch_feed_icon(&self, _feed_id: i64) -> Result<Option<String>, CoreError> {
        Err(CoreError::data("feed icon acquisition is unavailable"))
    }
    fn fetch_article_image(&self, _url: &str, _max_bytes: usize) -> Result<RemoteImage, CoreError> {
        Err(CoreError::data(
            "article thumbnail acquisition is unavailable",
        ))
    }
    fn fetch_article_by_id(&self, _article_id: i64) -> Result<RemoteSavedMediaArticle, CoreError> {
        Err(CoreError::data("article lookup is unavailable"))
    }
    fn fetch_media_range(
        &self,
        _url: &str,
        _range: &str,
        _max_bytes: usize,
    ) -> Result<Vec<u8>, CoreError> {
        Err(CoreError::data("media range probing is unavailable"))
    }
    fn miniflux_capabilities(&self) -> Result<Vec<MinifluxCapability>, CoreError> {
        Err(CoreError::data("Miniflux capabilities are unavailable"))
    }
    fn saved_media_sync_feeds(&self) -> Result<Vec<RemoteFeedInfo>, CoreError> {
        Err(CoreError::data(
            "SavedMedia sync feed discovery is unavailable",
        ))
    }
    fn update_saved_media_sync_feed(
        &self,
        _feed_id: i64,
        _title: Option<&str>,
        _disabled: bool,
    ) -> Result<(), CoreError> {
        Err(CoreError::data(
            "SavedMedia sync feed updates are unavailable",
        ))
    }
    fn saved_media_markers(&self, _feed_id: i64) -> Result<Vec<RemoteSavedMediaMarker>, CoreError> {
        Err(CoreError::data("SavedMedia marker fetch is unavailable"))
    }
    fn saved_media_markers_cancellable(
        &self,
        feed_id: i64,
        cancellation: &SyncCancellation,
    ) -> Result<Option<Vec<RemoteSavedMediaMarker>>, CoreError> {
        if cancellation.is_cancelled() {
            return Ok(None);
        }
        let result = self.saved_media_markers(feed_id);
        if cancellation.is_cancelled() {
            return Ok(None);
        }
        result.map(Some)
    }
    fn import_saved_media_marker(
        &self,
        _feed_id: i64,
        _external_id: &str,
        _article_id: i64,
        _enclosure_id: i64,
    ) -> Result<(), CoreError> {
        Err(CoreError::data("SavedMedia marker import is unavailable"))
    }
    fn set_saved_media_marker_state(&self, _entry_id: i64, _saved: bool) -> Result<(), CoreError> {
        Err(CoreError::data("SavedMedia marker updates are unavailable"))
    }
    fn fetch_saved_media_article(
        &self,
        _article_id: i64,
    ) -> Result<RemoteSavedMediaArticle, CoreError> {
        Err(CoreError::data(
            "SavedMedia source article fetch is unavailable",
        ))
    }
}

pub struct MinifluxClient {
    agent: ureq::Agent,
    media_probe_agent: ureq::Agent,
    installation_base: String,
    api_base: String,
    api_key: String,
    custom_headers: Vec<HttpHeader>,
    request_lock: Mutex<()>,
}

impl MinifluxClient {
    pub fn new(base_url: &str, api_key: &str) -> Result<Self, CoreError> {
        Self::new_with_headers(base_url, api_key, Vec::new())
    }
    pub fn new_with_headers(
        base_url: &str,
        api_key: &str,
        custom_headers: Vec<HttpHeader>,
    ) -> Result<Self, CoreError> {
        validate_custom_headers(&custom_headers)
            .map_err(|_| CoreError::invalid_configuration("custom HTTP headers are invalid"))?;
        let installation_base =
            normalize_installation_base(base_url).map_err(|error| match error {
                AccountValidationError::InvalidUrl => {
                    CoreError::invalid_configuration("base URL is invalid")
                }
                AccountValidationError::UnsupportedUrlScheme => {
                    CoreError::invalid_configuration("base URL must use HTTP(S)")
                }
                _ => unreachable!("URL normalization only returns URL errors"),
            })?;
        let api_base = format!("{installation_base}/v1");
        let mut agent_builder = ureq::Agent::config_builder()
            // Keep slow-but-progressing API transfers viable while failing a dead
            // route much earlier. This especially limits stalls when DNS returns
            // an unusable address family before a working alternative.
            .timeout_global(Some(REQUEST_TIMEOUT))
            .timeout_connect(Some(CONNECT_TIMEOUT))
            .timeout_recv_response(Some(READ_TIMEOUT))
            .timeout_recv_body(Some(READ_TIMEOUT))
            .timeout_send_request(Some(WRITE_TIMEOUT))
            .timeout_send_body(Some(WRITE_TIMEOUT))
            .max_redirects(10);
        let mut media_probe_builder = ureq::Agent::config_builder()
            .timeout_global(Some(MEDIA_PROBE_TIMEOUT))
            .timeout_connect(Some(MEDIA_PROBE_CONNECT_TIMEOUT))
            .timeout_recv_response(Some(MEDIA_PROBE_READ_TIMEOUT))
            .timeout_recv_body(Some(MEDIA_PROBE_READ_TIMEOUT))
            .timeout_send_request(Some(MEDIA_PROBE_READ_TIMEOUT))
            .timeout_send_body(Some(MEDIA_PROBE_READ_TIMEOUT))
            .max_redirects(5);
        #[cfg(any(target_vendor = "apple", target_os = "android"))]
        {
            agent_builder = agent_builder.tls_config(platform_tls_config());
            media_probe_builder = media_probe_builder.tls_config(platform_tls_config());
        }
        Ok(Self {
            agent: agent_builder.build().into(),
            media_probe_agent: media_probe_builder.build().into(),
            installation_base,
            api_base,
            api_key: api_key.to_string(),
            custom_headers,
            request_lock: Mutex::new(()),
        })
    }
    fn authenticated_request<B>(
        &self,
        mut request: ureq::RequestBuilder<B>,
    ) -> ureq::RequestBuilder<B> {
        for header in &self.custom_headers {
            request = request.header(&header.name, &header.value);
        }
        request.header("X-Auth-Token", &self.api_key)
    }
    pub fn installation_base(&self) -> &str {
        &self.installation_base
    }
    fn api_url(&self, path: &str) -> String {
        debug_assert!(path == "/v1" || path.starts_with("/v1/"));
        format!(
            "{}{}",
            self.api_base,
            path.strip_prefix("/v1").unwrap_or(path)
        )
    }
    fn get<T: for<'a> Deserialize<'a>>(
        &self,
        path: &str,
        query: &[(&str, String)],
    ) -> Result<T, CoreError> {
        let _request = self
            .request_lock
            .lock()
            .map_err(|_| CoreError::internal("HTTP client lock poisoned"))?;
        let mut serializer = url::form_urlencoded::Serializer::new(String::new());
        for (key, value) in query {
            serializer.append_pair(key, value);
        }
        let suffix = serializer.finish();
        let url = if suffix.is_empty() {
            self.api_url(path)
        } else {
            format!("{}?{suffix}", self.api_url(path))
        };
        let started = Instant::now();
        tracing::debug!(target: "miniflux", "request started endpoint={path}");
        let response = match self
            .authenticated_request(self.agent.get(&url))
            .header("Accept", "application/json")
            .call()
            .map_err(map_http_error)
        {
            Ok(response) => response,
            Err(error) => {
                log_request_failure(path, &error, started.elapsed());
                return Err(error);
            }
        };
        let decoded = serde_json::from_reader(response.into_body().into_reader())
            .map_err(|e| CoreError::data(format!("invalid Miniflux response: {e}")));
        match decoded {
            Ok(value) => {
                tracing::debug!(target: "miniflux", "request completed endpoint={} elapsed_ms={}", path, started.elapsed().as_millis());
                Ok(value)
            }
            Err(error) => {
                tracing::warn!(target: "miniflux", "response decoding failed endpoint={} kind={:?} elapsed_ms={}", path, error.kind, started.elapsed().as_millis());
                Err(error)
            }
        }
    }
    fn put(&self, path: &str, body: String) -> Result<(), CoreError> {
        let _request = self
            .request_lock
            .lock()
            .map_err(|_| CoreError::internal("HTTP client lock poisoned"))?;
        let started = Instant::now();
        tracing::debug!(target: "miniflux", "request started endpoint={path}");
        match self
            .authenticated_request(self.agent.put(&self.api_url(path)))
            .header("Content-Type", "application/json")
            .send(&body)
            .map_err(map_http_error)
        {
            Ok(_) => {
                tracing::debug!(target: "miniflux", "request completed endpoint={} elapsed_ms={}", path, started.elapsed().as_millis());
                Ok(())
            }
            Err(error) => {
                log_request_failure(path, &error, started.elapsed());
                Err(error)
            }
        }
    }
    fn post_json_status(
        &self,
        path: &str,
        body: serde_json::Value,
        expected: &[u16],
    ) -> Result<(), CoreError> {
        let _request = self
            .request_lock
            .lock()
            .map_err(|_| CoreError::internal("HTTP client lock poisoned"))?;
        let body = serde_json::to_string(&body)
            .map_err(|error| CoreError::internal(format!("encode Miniflux request: {error}")))?;
        let response = self
            .authenticated_request(self.agent.post(&self.api_url(path)))
            .header("Content-Type", "application/json")
            .send(&body)
            .map_err(map_http_error)?;
        if expected.contains(&response.status().as_u16()) {
            Ok(())
        } else {
            Err(CoreError::data(format!(
                "Miniflux returned unexpected HTTP {}",
                response.status().as_u16()
            )))
        }
    }
    fn save_to_service(&self, article_id: i64) -> Result<SaveToServiceResult, CoreError> {
        let path = format!("/v1/entries/{article_id}/save");
        let _request = self
            .request_lock
            .lock()
            .map_err(|_| CoreError::internal("HTTP client lock poisoned"))?;
        let started = Instant::now();
        tracing::debug!(target: "miniflux", "request started endpoint={path}");
        match self
            .authenticated_request(self.agent.post(&self.api_url(&path)))
            .config()
            .http_status_as_error(false)
            .build()
            .send_empty()
        {
            Ok(response) if response.status().as_u16() == 202 => {
                tracing::debug!(target: "miniflux", "request completed endpoint={} elapsed_ms={}", path, started.elapsed().as_millis());
                Ok(SaveToServiceResult::Saved)
            }
            Ok(response) if response.status().as_u16() == 400 => {
                let configured =
                    serde_json::from_reader::<_, ErrorDto>(response.into_body().into_reader())
                        .map(|body| body.error_message != "no third-party integration enabled")
                        .unwrap_or(true);
                if configured {
                    let error = CoreError::invalid_configuration("Miniflux returned HTTP 400")
                        .with_http_status(400);
                    log_request_failure(&path, &error, started.elapsed());
                    Err(error)
                } else {
                    tracing::debug!(target: "miniflux", "request completed without configured integration endpoint={} elapsed_ms={}", path, started.elapsed().as_millis());
                    Ok(SaveToServiceResult::NoIntegrationConfigured)
                }
            }
            Ok(response) => {
                let error = map_http_error(ureq::Error::StatusCode(response.status().as_u16()));
                log_request_failure(&path, &error, started.elapsed());
                Err(error)
            }
            Err(error) => {
                let error = map_http_error(error);
                log_request_failure(&path, &error, started.elapsed());
                Err(error)
            }
        }
    }
    fn post_json<T: for<'a> Deserialize<'a>>(
        &self,
        path: &str,
        body: serde_json::Value,
        expected_status: u16,
    ) -> Result<T, CoreError> {
        let _request = self
            .request_lock
            .lock()
            .map_err(|_| CoreError::internal("HTTP client lock poisoned"))?;
        let body = serde_json::to_string(&body)
            .map_err(|error| CoreError::internal(format!("encode Miniflux request: {error}")))?;
        let started = Instant::now();
        tracing::debug!(target: "miniflux", "request started endpoint={path}");
        let response = match self
            .authenticated_request(self.agent.post(&self.api_url(path)))
            .header("Content-Type", "application/json")
            .send(&body)
            .map_err(map_http_error)
        {
            Ok(response) => response,
            Err(error) => {
                log_request_failure(path, &error, started.elapsed());
                return Err(error);
            }
        };
        if response.status().as_u16() != expected_status {
            let error = CoreError::data(format!(
                "Miniflux returned unexpected HTTP {}",
                response.status().as_u16()
            ))
            .with_http_status(response.status().as_u16());
            log_request_failure(path, &error, started.elapsed());
            return Err(error);
        }
        let decoded = serde_json::from_reader(response.into_body().into_reader())
            .map_err(|error| CoreError::data(format!("invalid Miniflux response: {error}")));
        match decoded {
            Ok(value) => {
                tracing::debug!(target: "miniflux", "request completed endpoint={} elapsed_ms={}", path, started.elapsed().as_millis());
                Ok(value)
            }
            Err(error) => {
                tracing::warn!(target: "miniflux", "response decoding failed endpoint={} kind={:?} elapsed_ms={}", path, error.kind, started.elapsed().as_millis());
                Err(error)
            }
        }
    }
    fn discover_subscriptions(
        &self,
        request: DiscoverSubscriptionsRequest,
    ) -> Result<Vec<DiscoveredSubscription>, CoreError> {
        let response: Vec<DiscoveredSubscriptionDto> =
            self.post_json("/v1/discover", discovery_request_json(request), 200)?;
        Ok(response
            .into_iter()
            .map(|subscription| DiscoveredSubscription {
                url: subscription.url,
                title: subscription.title,
                feed_type: subscription.feed_type,
            })
            .collect())
    }
    fn create_feed(&self, request: CreateFeedRequest) -> Result<CreateFeedResult, CoreError> {
        let response: CreateFeedDto =
            self.post_json("/v1/feeds", create_feed_request_json(request), 201)?;
        Ok(CreateFeedResult {
            feed_id: response.feed_id,
        })
    }
    fn create_category(&self, title: String) -> Result<CreateCategoryResult, CoreError> {
        let response: CreateCategoryDto =
            self.post_json("/v1/categories", serde_json::json!({ "title": title }), 201)?;
        Ok(CreateCategoryResult {
            category_id: response.id,
        })
    }
    #[cfg(test)]
    fn entries(&self, status: Option<&str>, starred: bool) -> Result<Vec<EntryDto>, CoreError> {
        self.entries_with_cancellation(status, starred, None)?
            .ok_or_else(|| CoreError::internal("uncancellable entry fetch was cancelled"))
    }

    fn changed_entries_with_cancellation(
        &self,
        changed_after: i64,
        cancellation: &SyncCancellation,
    ) -> Result<Option<RemoteDelta>, CoreError> {
        const CURSOR_OVERLAP_SECONDS: i64 = 2;
        let query_after = changed_after.saturating_sub(CURSOR_OVERLAP_SECONDS).max(0);
        let Some(window_end) = self.delta_watermark_with_cancellation(cancellation)? else {
            return Ok(None);
        };
        let cursor = changed_after.max(window_end);
        let changed_before = window_end.saturating_add(1);
        let started = Instant::now();
        tracing::info!(
            target: "miniflux",
            "delta entry fetch started changed_after={} query_after={} window_end={}",
            changed_after,
            query_after,
            window_end
        );
        let mut all = Vec::new();
        let mut after_id = 0;
        loop {
            if cancellation.is_cancelled() {
                return Ok(None);
            }
            let mut query = vec![
                ("changed_after", query_after.to_string()),
                ("changed_before", changed_before.to_string()),
                ("limit", PAGE_SIZE.to_string()),
                ("order", "id".to_string()),
                ("direction", "asc".to_string()),
            ];
            if after_id > 0 {
                query.push(("after_entry_id", after_id.to_string()));
            }
            let page_result: Result<EntriesDto, CoreError> = self.get("/v1/entries", &query);
            if cancellation.is_cancelled() {
                return Ok(None);
            }
            let page = page_result?;
            if page.entries.is_empty() {
                break;
            }
            let mut previous = after_id;
            for entry in &page.entries {
                if entry.id <= previous {
                    return Err(CoreError::data(
                        "Miniflux returned unstable delta entry pagination",
                    ));
                }
                previous = entry.id;
                // Validate changed_at while parsing the bounded window. Cursor
                // advancement itself uses the pre-fetch high-water mark so
                // concurrent changes after window_end remain for the next run.
                let _ = entry_changed_at_unix(entry)?;
            }
            after_id = previous;
            all.extend(page.entries);
        }

        let mut articles = Vec::with_capacity(all.len());
        let mut enclosures = Vec::new();
        for entry in all {
            if cancellation.is_cancelled() {
                return Ok(None);
            }
            let entry_enclosures = map_enclosures(entry.id, entry.enclosures)?;
            let enclosure_inputs = entry_enclosures
                .iter()
                .map(|item| crate::article::EnclosureInput {
                    url: item.url.clone(),
                    mime_type: item.mime_type.clone(),
                })
                .collect::<Vec<_>>();
            let published = DateTime::parse_from_rfc3339(&entry.published_at).map_err(|_| {
                CoreError::data(format!("article {} has invalid publication time", entry.id))
            })?;
            let processed = crate::article::process(&entry.content, &entry.url, &enclosure_inputs);
            enclosures.extend(entry_enclosures);
            articles.push(Article {
                id: entry.id,
                feed_id: entry.feed_id,
                title: entry.title,
                url: entry.url,
                comments_url: entry.comments_url,
                published_at: published
                    .to_utc()
                    .to_rfc3339_opts(SecondsFormat::Secs, true),
                // Miniflux's removed state is not an unread state. Full Sync
                // eventually reconciles structural/removal truth.
                is_read: entry.status != "unread",
                is_starred: entry.starred,
                raw_html_content: entry.content,
                reading_time_minutes: entry.reading_time,
                preview: processed.preview,
                image_url: processed.image_url,
            });
        }
        tracing::info!(
            target: "miniflux",
            "delta entry fetch completed entries={} cursor={} elapsed_ms={}",
            articles.len(),
            cursor,
            started.elapsed().as_millis()
        );
        Ok(Some(RemoteDelta {
            articles,
            enclosures,
            cursor,
        }))
    }

    fn delta_watermark_with_cancellation(
        &self,
        cancellation: &SyncCancellation,
    ) -> Result<Option<i64>, CoreError> {
        if cancellation.is_cancelled() {
            return Ok(None);
        }
        let result: Result<EntriesDto, CoreError> = self.get(
            "/v1/entries",
            &[
                ("limit", "1".to_string()),
                ("order", "changed_at".to_string()),
                ("direction", "desc".to_string()),
            ],
        );
        if cancellation.is_cancelled() {
            return Ok(None);
        }
        let page = result?;
        let cursor = page
            .entries
            .first()
            .map(entry_changed_at_unix)
            .transpose()?
            .unwrap_or(0);
        Ok(Some(cursor))
    }

    fn entries_with_cancellation(
        &self,
        status: Option<&str>,
        starred: bool,
        cancellation: Option<&SyncCancellation>,
    ) -> Result<Option<Vec<EntryDto>>, CoreError> {
        let set = if starred {
            "starred"
        } else {
            status.unwrap_or("all")
        };
        let started = Instant::now();
        tracing::info!(target: "miniflux", "entry fetch started set={set}");
        let mut all = Vec::new();
        let mut after_id = 0;
        loop {
            if cancellation.is_some_and(SyncCancellation::is_cancelled) {
                return Ok(None);
            }
            let mut query = vec![
                ("limit", PAGE_SIZE.to_string()),
                ("order", "id".to_string()),
                ("direction", "asc".to_string()),
            ];
            if let Some(status) = status {
                query.push(("status", status.to_string()));
            }
            if starred {
                query.push(("starred", "1".to_string()));
            }
            if after_id > 0 {
                query.push(("after_entry_id", after_id.to_string()));
            }
            let page_result: Result<EntriesDto, CoreError> = self.get("/v1/entries", &query);
            if cancellation.is_some_and(SyncCancellation::is_cancelled) {
                return Ok(None);
            }
            let page = page_result?;
            tracing::debug!(target: "miniflux", "entry page completed set={} entries={} total={} accumulated={} after_entry_id={}", set, page.entries.len(), page.total, all.len(), after_id);
            if page.entries.is_empty() {
                break;
            }
            let mut previous = after_id;
            for entry in &page.entries {
                if entry.id <= previous {
                    return Err(CoreError::data(
                        "Miniflux returned unstable entry pagination",
                    ));
                }
                previous = entry.id;
            }
            after_id = previous;
            all.extend(page.entries);
        }
        tracing::info!(target: "miniflux", "entry fetch completed set={} entries={} elapsed_ms={}", set, all.len(), started.elapsed().as_millis());
        Ok(Some(all))
    }

    fn saved_media_markers(&self, feed_id: i64) -> Result<Vec<RemoteSavedMediaMarker>, CoreError> {
        self.saved_media_markers_with_cancellation(feed_id, None)?
            .ok_or_else(|| {
                CoreError::internal("uncancellable SavedMedia marker fetch was cancelled")
            })
    }

    fn saved_media_markers_with_cancellation(
        &self,
        feed_id: i64,
        cancellation: Option<&SyncCancellation>,
    ) -> Result<Option<Vec<RemoteSavedMediaMarker>>, CoreError> {
        let mut entries = Vec::new();
        for status in ["unread", "read", "removed"] {
            if cancellation.is_some_and(SyncCancellation::is_cancelled) {
                return Ok(None);
            }
            let Some(status_entries) =
                self.entries_for_feed_status_with_cancellation(feed_id, status, cancellation)?
            else {
                return Ok(None);
            };
            entries.extend(status_entries);
        }
        Ok(Some(
            entries
                .into_iter()
                .filter_map(|entry| {
                    entry.external_id.map(|external_id| RemoteSavedMediaMarker {
                        entry_id: entry.id,
                        external_id,
                        status: entry.status,
                    })
                })
                .collect(),
        ))
    }

    fn entries_for_feed_status_with_cancellation(
        &self,
        feed_id: i64,
        status: &str,
        cancellation: Option<&SyncCancellation>,
    ) -> Result<Option<Vec<EntryDto>>, CoreError> {
        let mut all = Vec::new();
        let mut after_id = 0;
        loop {
            if cancellation.is_some_and(SyncCancellation::is_cancelled) {
                return Ok(None);
            }
            let mut query = vec![
                ("feed_id", feed_id.to_string()),
                ("status", status.to_string()),
                ("limit", PAGE_SIZE.to_string()),
                ("order", "id".to_string()),
                ("direction", "asc".to_string()),
            ];
            if after_id > 0 {
                query.push(("after_entry_id", after_id.to_string()));
            }
            let page_result: Result<EntriesDto, CoreError> = self.get("/v1/entries", &query);
            if cancellation.is_some_and(SyncCancellation::is_cancelled) {
                return Ok(None);
            }
            let page = page_result?;
            if page.entries.is_empty() {
                break;
            }
            let mut previous = after_id;
            for entry in &page.entries {
                if entry.id <= previous {
                    return Err(CoreError::data(
                        "Miniflux returned unstable entry pagination",
                    ));
                }
                previous = entry.id;
            }
            after_id = previous;
            all.extend(page.entries);
        }
        Ok(Some(all))
    }

    fn saved_media_article(&self, article_id: i64) -> Result<RemoteSavedMediaArticle, CoreError> {
        let entry: EntryDto = self.get(&format!("/v1/entries/{article_id}"), &[])?;
        entry_to_saved_media_article(entry)
    }
    fn fetch_media_range(
        &self,
        url: &str,
        range: &str,
        max_bytes: usize,
    ) -> Result<Vec<u8>, CoreError> {
        if max_bytes == 0 {
            return Ok(Vec::new());
        }
        let parsed =
            url::Url::parse(url).map_err(|_| CoreError::data("media probe URL is invalid"))?;
        if !matches!(parsed.scheme(), "http" | "https") || parsed.host_str().is_none() {
            return Err(CoreError::data("media probe URL must use HTTP(S)"));
        }

        let response = self
            .media_probe_agent
            .get(url)
            .header(
                "Accept",
                "audio/*,video/*,application/octet-stream;q=0.8,*/*;q=0.1",
            )
            .header("Range", range)
            .call()
            .map_err(map_http_error)?;

        let status = response.status().as_u16();
        if status != 206 {
            let length = response
                .headers()
                .get("Content-Length")
                .and_then(|value| value.to_str().ok())
                .and_then(|value| value.parse::<usize>().ok());
            if status != 200 || length.is_none_or(|length| length > max_bytes) {
                return Err(CoreError::data(
                    "media server ignored bounded Range request",
                ));
            }
        }

        if response
            .headers()
            .get("Content-Length")
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.parse::<usize>().ok())
            .is_some_and(|length| length > max_bytes)
        {
            return Err(CoreError::data("media probe response exceeds byte budget"));
        }

        let mut reader = response
            .into_body()
            .into_reader()
            .take((max_bytes + 1) as u64);
        let mut bytes = Vec::with_capacity(max_bytes.min(256 * 1024));
        reader.read_to_end(&mut bytes).map_err(|error| {
            CoreError::connectivity(format!("media probe read failed: {error}"))
        })?;
        if bytes.len() > max_bytes {
            return Err(CoreError::data("media probe response exceeds byte budget"));
        }
        Ok(bytes)
    }

    fn search_articles(
        &self,
        request: SearchArticlesRequest,
    ) -> Result<SearchArticlesResult, CoreError> {
        let page: EntriesDto = self.get(
            "/v1/entries",
            &[
                ("search", request.query),
                ("order", "published_at".into()),
                ("direction", "desc".into()),
                ("offset", request.offset.to_string()),
                ("limit", request.limit.to_string()),
            ],
        )?;
        let articles = page
            .entries
            .into_iter()
            .map(search_article_summary)
            .collect::<Result<_, _>>()?;
        Ok(SearchArticlesResult {
            total: page.total,
            articles,
        })
    }
    fn download_image(&self, url: &str, max_bytes: usize) -> Result<RemoteImage, CoreError> {
        let response = self
            .agent
            .get(url)
            .header("Accept", "image/*")
            .call()
            .map_err(map_image_http_error)?;
        if response
            .headers()
            .get("Content-Length")
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.parse::<usize>().ok())
            .is_some_and(|length| length > max_bytes)
        {
            return Err(CoreError::data("article image exceeds maximum payload"));
        }
        let content_type = response
            .headers()
            .get("Content-Type")
            .and_then(|value| value.to_str().ok())
            .map(str::to_owned);
        let mut reader = response
            .into_body()
            .into_reader()
            .take((max_bytes + 1) as u64);
        let mut bytes = Vec::with_capacity(max_bytes.min(64 * 1024));
        reader.read_to_end(&mut bytes).map_err(|error| {
            CoreError::connectivity(format!("article image download failed: {error}"))
        })?;
        if bytes.len() > max_bytes {
            return Err(CoreError::data("article image exceeds maximum payload"));
        }
        Ok(RemoteImage {
            content_type,
            bytes,
        })
    }

    fn fetch_initial_articles_with_cancellation(
        &self,
        cancellation: Option<&SyncCancellation>,
    ) -> Result<Option<RemoteSnapshot>, CoreError> {
        if cancellation.is_some_and(SyncCancellation::is_cancelled) {
            return Ok(None);
        }
        let categories_result: Result<Vec<CategoryDto>, CoreError> =
            self.get("/v1/categories", &[]);
        if cancellation.is_some_and(SyncCancellation::is_cancelled) {
            return Ok(None);
        }
        let categories = categories_result?;
        let feeds_result: Result<Vec<FeedDto>, CoreError> = self.get("/v1/feeds", &[]);
        if cancellation.is_some_and(SyncCancellation::is_cancelled) {
            return Ok(None);
        }
        let feeds = feeds_result?;
        let categories = categories
            .into_iter()
            .map(|c| Category {
                id: c.id,
                title: c.title,
            })
            .collect();
        let feeds: Vec<Feed> = feeds
            .into_iter()
            .map(|f| Feed {
                id: f.id,
                category_id: f.category.map(|c| c.id).unwrap_or_default(),
                title: f.title,
            })
            .collect();
        let feed_ids: HashMap<i64, _> = feeds.iter().map(|f| (f.id, ())).collect();
        let mut entries = HashMap::new();

        let Some(unread) = self.entries_with_cancellation(Some("unread"), false, cancellation)?
        else {
            return Ok(None);
        };
        for entry in unread {
            entries.insert(entry.id, entry);
        }
        let Some(starred) = self.entries_with_cancellation(None, true, cancellation)? else {
            return Ok(None);
        };
        for entry in starred {
            entries.insert(entry.id, entry);
        }

        let mut articles = Vec::with_capacity(entries.len());
        let mut enclosures = Vec::new();
        for entry in entries.into_values() {
            if cancellation.is_some_and(SyncCancellation::is_cancelled) {
                return Ok(None);
            }
            if !feed_ids.contains_key(&entry.feed_id) {
                return Err(CoreError::data(format!(
                    "article {} references unknown feed {}",
                    entry.id, entry.feed_id
                )));
            }
            let published = DateTime::parse_from_rfc3339(&entry.published_at).map_err(|_| {
                CoreError::data(format!("article {} has invalid publication time", entry.id))
            })?;
            let entry_enclosures = map_enclosures(entry.id, entry.enclosures)?;
            let enclosure_inputs = entry_enclosures
                .iter()
                .map(|item| crate::article::EnclosureInput {
                    url: item.url.clone(),
                    mime_type: item.mime_type.clone(),
                })
                .collect::<Vec<_>>();
            let processed = crate::article::process(&entry.content, &entry.url, &enclosure_inputs);
            enclosures.extend(entry_enclosures);
            articles.push(Article {
                id: entry.id,
                feed_id: entry.feed_id,
                title: entry.title,
                url: entry.url,
                comments_url: entry.comments_url,
                published_at: published
                    .to_utc()
                    .to_rfc3339_opts(SecondsFormat::Secs, true),
                is_read: entry.status == "read",
                is_starred: entry.starred,
                raw_html_content: entry.content,
                reading_time_minutes: entry.reading_time,
                preview: processed.preview,
                image_url: processed.image_url,
            });
        }
        if cancellation.is_some_and(SyncCancellation::is_cancelled) {
            return Ok(None);
        }
        Ok(Some(RemoteSnapshot {
            categories,
            feeds,
            articles,
            enclosures,
        }))
    }

    pub fn validate_account(
        server_url: &str,
        api_key: &str,
        custom_headers: Vec<HttpHeader>,
    ) -> Result<AccountValidationResult, AccountValidationError> {
        let attempt = Self::validate_account_with_diagnostic(server_url, api_key, custom_headers);
        match (attempt.result, attempt.error) {
            (Some(result), _) => Ok(result),
            (_, Some(error)) => Err(error),
            (None, None) => Err(AccountValidationError::InvalidResponse),
        }
    }

    pub fn validate_account_with_diagnostic(
        server_url: &str,
        api_key: &str,
        custom_headers: Vec<HttpHeader>,
    ) -> AccountValidationAttempt {
        match Self::validate_account_inner(server_url, api_key, custom_headers) {
            Ok(result) => AccountValidationAttempt {
                result: Some(result),
                error: None,
                diagnostic: None,
            },
            Err(failure) => AccountValidationAttempt {
                result: None,
                error: Some(failure.error),
                diagnostic: failure.diagnostic,
            },
        }
    }

    fn validate_account_inner(
        server_url: &str,
        api_key: &str,
        custom_headers: Vec<HttpHeader>,
    ) -> Result<AccountValidationResult, AccountValidationFailure> {
        if api_key.is_empty() {
            return Err(AccountValidationFailure::without_diagnostic(
                AccountValidationError::Unauthorized,
            ));
        }
        validate_custom_headers(&custom_headers)
            .map_err(AccountValidationFailure::without_diagnostic)?;
        let installation_base = normalize_installation_base(server_url)
            .map_err(AccountValidationFailure::without_diagnostic)?;
        let secret_values = custom_headers
            .iter()
            .map(|header| header.value.clone())
            .chain(std::iter::once(api_key.to_owned()))
            .collect::<Vec<_>>();
        let client =
            Self::new_with_headers(&installation_base, api_key, custom_headers).map_err(|_| {
                AccountValidationFailure::without_diagnostic(AccountValidationError::InvalidUrl)
            })?;
        let _request = client.request_lock.lock().map_err(|_| {
            AccountValidationFailure::without_diagnostic(AccountValidationError::Network)
        })?;
        let response = client
            .authenticated_request(client.agent.get(&client.api_url("/v1/version")))
            .header("Accept", "application/json")
            .call()
            .map_err(|error| AccountValidationFailure {
                error: map_account_validation_error(&error),
                diagnostic: account_validation_diagnostic(&error, &secret_values),
            })?;
        let response: VersionDto = serde_json::from_reader(response.into_body().into_reader())
            .map_err(|_| {
                AccountValidationFailure::without_diagnostic(
                    AccountValidationError::InvalidResponse,
                )
            })?;
        if response.version.trim().is_empty() {
            return Err(AccountValidationFailure::without_diagnostic(
                AccountValidationError::InvalidResponse,
            ));
        }
        Ok(AccountValidationResult {
            installation_base: client.installation_base,
            version: response.version,
        })
    }
}

/// Platform-trust TLS configuration for targets whose operating system owns the
/// certificate store Flux must honour.
///
/// Apple platforms verify against the system roots plus the keychain. Android verifies
/// against the Android trust infrastructure, which covers system and user-installed
/// anchors; that path requires [`crate::miniflux`] consumers to have completed the
/// Android verifier bootstrap before the first request. Every other target keeps the
/// `ureq` default TLS configuration.
#[cfg(any(target_vendor = "apple", target_os = "android"))]
fn platform_tls_config() -> ureq::tls::TlsConfig {
    ureq::tls::TlsConfig::builder()
        .root_certs(ureq::tls::RootCerts::PlatformVerifier)
        .build()
}

#[derive(Debug)]
struct AccountValidationFailure {
    error: AccountValidationError,
    diagnostic: Option<AccountValidationDiagnostic>,
}

impl AccountValidationFailure {
    fn without_diagnostic(error: AccountValidationError) -> Self {
        Self {
            error,
            diagnostic: None,
        }
    }
}

impl RemoteSource for MinifluxClient {
    fn fetch_initial_articles(&self) -> Result<RemoteSnapshot, CoreError> {
        self.fetch_initial_articles_with_cancellation(None)?
            .ok_or_else(|| CoreError::internal("uncancellable initial fetch was cancelled"))
    }

    fn fetch_initial_articles_cancellable(
        &self,
        cancellation: &SyncCancellation,
    ) -> Result<Option<RemoteSnapshot>, CoreError> {
        self.fetch_initial_articles_with_cancellation(Some(cancellation))
    }

    fn fetch_changed_articles_cancellable(
        &self,
        changed_after: i64,
        cancellation: &SyncCancellation,
    ) -> Result<Option<RemoteDelta>, CoreError> {
        self.changed_entries_with_cancellation(changed_after, cancellation)
    }

    fn delta_watermark_cancellable(
        &self,
        cancellation: &SyncCancellation,
    ) -> Result<Option<i64>, CoreError> {
        self.delta_watermark_with_cancellation(cancellation)
    }

    fn set_read_state(&self, article_ids: &[i64], read: bool) -> Result<(), CoreError> {
        let ids = article_ids
            .iter()
            .map(ToString::to_string)
            .collect::<Vec<_>>()
            .join(",");
        let status = if read { "read" } else { "unread" };
        self.put(
            "/v1/entries",
            format!(r#"{{"entry_ids":[{ids}],"status":"{status}"}}"#),
        )
    }
    fn set_starred_state(&self, article_id: i64, starred: bool) -> Result<(), CoreError> {
        let cancellation = SyncCancellation::new();
        if self.set_starred_state_cancellable(article_id, starred, &cancellation)? {
            Ok(())
        } else {
            unreachable!("fresh cancellation signal cannot be cancelled")
        }
    }
    fn set_starred_state_cancellable(
        &self,
        article_id: i64,
        starred: bool,
        cancellation: &SyncCancellation,
    ) -> Result<bool, CoreError> {
        if cancellation.is_cancelled() {
            return Ok(false);
        }
        let entry_result: Result<EntryDto, CoreError> =
            self.get(&format!("/v1/entries/{article_id}"), &[]);
        if cancellation.is_cancelled() {
            return Ok(false);
        }
        let entry = entry_result?;
        if entry.starred != starred {
            if cancellation.is_cancelled() {
                return Ok(false);
            }
            let update_result = self.put(&format!("/v1/entries/{article_id}/star"), String::new());
            if cancellation.is_cancelled() {
                return Ok(false);
            }
            update_result?;
        }
        Ok(true)
    }
    fn set_media_progression(&self, enclosure_id: i64, seconds: u64) -> Result<(), CoreError> {
        self.put(
            &format!("/v1/enclosures/{enclosure_id}"),
            serde_json::json!({ "media_progression": seconds }).to_string(),
        )
    }
    fn search_articles(
        &self,
        request: SearchArticlesRequest,
    ) -> Result<SearchArticlesResult, CoreError> {
        MinifluxClient::search_articles(self, request)
    }
    fn save_to_service(&self, article_id: i64) -> Result<SaveToServiceResult, CoreError> {
        MinifluxClient::save_to_service(self, article_id)
    }
    fn discover_subscriptions(
        &self,
        request: DiscoverSubscriptionsRequest,
    ) -> Result<Vec<DiscoveredSubscription>, CoreError> {
        MinifluxClient::discover_subscriptions(self, request)
    }
    fn create_feed(&self, request: CreateFeedRequest) -> Result<CreateFeedResult, CoreError> {
        MinifluxClient::create_feed(self, request)
    }
    fn create_category(&self, title: String) -> Result<CreateCategoryResult, CoreError> {
        MinifluxClient::create_category(self, title)
    }
    fn fetch_feed_icon(&self, feed_id: i64) -> Result<Option<String>, CoreError> {
        let icon: IconDto = match self.get(&format!("/v1/feeds/{feed_id}/icon"), &[]) {
            Ok(icon) => icon,
            Err(error) if error.message == "Miniflux returned HTTP 404" => return Ok(None),
            Err(error) => return Err(error),
        };
        Ok(icon.data_url())
    }
    fn fetch_article_image(&self, url: &str, max_bytes: usize) -> Result<RemoteImage, CoreError> {
        self.download_image(url, max_bytes)
    }
    fn fetch_media_range(
        &self,
        url: &str,
        range: &str,
        max_bytes: usize,
    ) -> Result<Vec<u8>, CoreError> {
        MinifluxClient::fetch_media_range(self, url, range, max_bytes)
    }
    fn miniflux_capabilities(&self) -> Result<Vec<MinifluxCapability>, CoreError> {
        let version: VersionDto = self.get("/v1/version", &[])?;
        Ok(MinifluxCapability::all_supported_by(&version.version))
    }
    fn saved_media_sync_feeds(&self) -> Result<Vec<RemoteFeedInfo>, CoreError> {
        let feeds: Vec<FeedDto> = self.get("/v1/feeds", &[])?;
        Ok(feeds
            .into_iter()
            .map(|feed| RemoteFeedInfo {
                id: feed.id,
                title: feed.title,
                feed_url: feed.feed_url,
                disabled: feed.disabled,
            })
            .collect())
    }
    fn update_saved_media_sync_feed(
        &self,
        feed_id: i64,
        title: Option<&str>,
        disabled: bool,
    ) -> Result<(), CoreError> {
        let mut body = serde_json::Map::new();
        body.insert("disabled".into(), disabled.into());
        if let Some(title) = title {
            body.insert("title".into(), title.into());
        }
        self.put(
            &format!("/v1/feeds/{feed_id}"),
            serde_json::Value::Object(body).to_string(),
        )
    }
    fn saved_media_markers(&self, feed_id: i64) -> Result<Vec<RemoteSavedMediaMarker>, CoreError> {
        MinifluxClient::saved_media_markers(self, feed_id)
    }
    fn saved_media_markers_cancellable(
        &self,
        feed_id: i64,
        cancellation: &SyncCancellation,
    ) -> Result<Option<Vec<RemoteSavedMediaMarker>>, CoreError> {
        self.saved_media_markers_with_cancellation(feed_id, Some(cancellation))
    }
    fn import_saved_media_marker(
        &self,
        feed_id: i64,
        external_id: &str,
        article_id: i64,
        enclosure_id: i64,
    ) -> Result<(), CoreError> {
        self.post_json_status(&format!("/v1/feeds/{feed_id}/entries/import"), serde_json::json!({
            "title": "Flux Saved Media marker",
            "url": format!("https://flux.invalid/saved-media/{article_id}/{enclosure_id}"),
            "content": format!("flux:saved-media:v1 article_id={article_id} enclosure_id={enclosure_id}"),
            "external_id": external_id,
        }), &[200, 201])
    }
    fn set_saved_media_marker_state(&self, entry_id: i64, saved: bool) -> Result<(), CoreError> {
        self.put("/v1/entries", serde_json::json!({ "entry_ids": [entry_id], "status": if saved { "unread" } else { "removed" } }).to_string())
    }
    fn fetch_saved_media_article(
        &self,
        article_id: i64,
    ) -> Result<RemoteSavedMediaArticle, CoreError> {
        MinifluxClient::saved_media_article(self, article_id)
    }
    fn fetch_article_by_id(&self, article_id: i64) -> Result<RemoteSavedMediaArticle, CoreError> {
        MinifluxClient::saved_media_article(self, article_id)
    }
}

fn map_http_error(error: ureq::Error) -> CoreError {
    match error {
        ureq::Error::StatusCode(status @ (401 | 403)) => {
            CoreError::authentication("Miniflux rejected credentials").with_http_status(status)
        }
        ureq::Error::StatusCode(status) if status == 429 || status >= 500 => {
            CoreError::server_transient(format!("Miniflux server returned HTTP {status}"))
                .with_http_status(status)
        }
        ureq::Error::StatusCode(status) => {
            CoreError::invalid_configuration(format!("Miniflux returned HTTP {status}"))
                .with_http_status(status)
        }
        other => CoreError::connectivity(format!("Miniflux request failed: {other}")),
    }
}
fn log_request_failure(path: &str, error: &CoreError, elapsed: std::time::Duration) {
    if let Some(status) = error.http_status() {
        tracing::warn!(target: "miniflux", "request failed endpoint={} status={} kind={:?} elapsed_ms={}", path, status, error.kind, elapsed.as_millis());
    } else {
        tracing::warn!(target: "miniflux", "request failed endpoint={} kind={:?} elapsed_ms={}", path, error.kind, elapsed.as_millis());
    }
}
fn map_account_validation_error(error: &ureq::Error) -> AccountValidationError {
    match error {
        ureq::Error::StatusCode(401) | ureq::Error::StatusCode(403) => {
            AccountValidationError::Unauthorized
        }
        ureq::Error::StatusCode(404) => AccountValidationError::IncompatibleServer,
        ureq::Error::StatusCode(status) if *status == 429 || *status >= 500 => {
            AccountValidationError::ServerUnavailable
        }
        ureq::Error::StatusCode(_) => AccountValidationError::IncompatibleServer,
        _ => AccountValidationError::Network,
    }
}

fn account_validation_diagnostic(
    error: &ureq::Error,
    secret_values: &[String],
) -> Option<AccountValidationDiagnostic> {
    match error {
        error if !matches!(error, ureq::Error::StatusCode(_)) => {
            let detail = sanitize_transport_detail(&error.to_string(), secret_values);
            let lower = detail.to_ascii_lowercase();
            let category = if matches!(error, ureq::Error::Tls(_) | ureq::Error::Rustls(_))
                || lower.contains("tls")
                || lower.contains("certificate")
                || lower.contains("cert ")
            {
                "TLS/certificate"
            } else if matches!(error, ureq::Error::HostNotFound) {
                "DNS resolution"
            } else if matches!(error, ureq::Error::Timeout(_))
                || lower.contains("timeout")
                || lower.contains("timed out")
            {
                "Timeout"
            } else if matches!(error, ureq::Error::ConnectionFailed | ureq::Error::Io(_)) {
                "Connection failed"
            } else {
                "Transport"
            };
            Some(AccountValidationDiagnostic {
                category: category.to_string(),
                detail,
            })
        }
        ureq::Error::StatusCode(status) if *status == 429 || *status >= 500 => {
            Some(AccountValidationDiagnostic {
                category: "HTTP server unavailable".to_string(),
                detail: format!("HTTP status {status}"),
            })
        }
        _ => None,
    }
}

fn sanitize_transport_detail(value: &str, secrets: &[String]) -> String {
    let mut sanitized = value.to_string();
    for secret in secrets.iter().filter(|secret| !secret.is_empty()) {
        sanitized = sanitized.replace(secret, "[REDACTED]");
    }
    sanitized
        .chars()
        .map(|character| {
            if character.is_control() {
                ' '
            } else {
                character
            }
        })
        .take(512)
        .collect()
}
fn map_image_http_error(error: ureq::Error) -> CoreError {
    match error {
        ureq::Error::StatusCode(status) if status == 429 || status >= 500 => {
            CoreError::server_transient(format!("article image server returned HTTP {status}"))
        }
        ureq::Error::StatusCode(status) => {
            CoreError::data(format!("article image returned HTTP {status}"))
        }
        other => CoreError::connectivity(format!("article image request failed: {other}")),
    }
}

#[derive(Deserialize)]
struct VersionDto {
    version: String,
}

#[derive(Deserialize)]
struct EntriesDto {
    #[serde(default)]
    total: i64,
    #[serde(default)]
    entries: Vec<EntryDto>,
}
#[derive(Deserialize)]
struct EntryDto {
    id: i64,
    feed_id: i64,
    #[serde(default)]
    title: String,
    #[serde(default)]
    url: String,
    #[serde(default)]
    comments_url: String,
    #[serde(default)]
    status: String,
    #[serde(default)]
    starred: bool,
    published_at: String,
    #[serde(default)]
    changed_at: String,
    #[serde(default)]
    content: String,
    #[serde(default)]
    reading_time: u32,
    #[serde(default)]
    external_id: Option<String>,
    #[serde(default)]
    enclosures: Vec<EnclosureDto>,
    feed: Option<FeedDto>,
}
#[derive(Deserialize)]
struct EnclosureDto {
    id: i64,
    entry_id: i64,
    #[serde(default)]
    url: String,
    #[serde(default)]
    mime_type: String,
    #[serde(default)]
    size: i64,
    #[serde(default)]
    media_progression: u64,
}
#[derive(Deserialize)]
struct CategoryDto {
    id: i64,
    #[serde(default)]
    title: String,
}
#[derive(Deserialize)]
struct FeedDto {
    id: i64,
    #[serde(default)]
    title: String,
    #[serde(default)]
    feed_url: String,
    #[serde(default)]
    disabled: bool,
    category: Option<CategoryRefDto>,
}

fn entry_changed_at_unix(entry: &EntryDto) -> Result<i64, CoreError> {
    DateTime::parse_from_rfc3339(&entry.changed_at)
        .map(|value| value.timestamp())
        .map_err(|_| CoreError::data(format!("article {} has invalid changed_at", entry.id)))
}

fn search_article_summary(entry: EntryDto) -> Result<ArticleSummary, CoreError> {
    let feed = entry.feed.ok_or_else(|| {
        CoreError::data(format!(
            "search article {} is missing feed metadata",
            entry.id
        ))
    })?;
    let category_id = feed
        .category
        .map(|category| category.id)
        .unwrap_or_default();
    let published = DateTime::parse_from_rfc3339(&entry.published_at).map_err(|_| {
        CoreError::data(format!("article {} has invalid publication time", entry.id))
    })?;
    let enclosures = entry
        .enclosures
        .iter()
        .map(|item| crate::article::EnclosureInput {
            url: item.url.clone(),
            mime_type: item.mime_type.clone(),
        })
        .collect::<Vec<_>>();
    let processed = crate::article::process(&entry.content, &entry.url, &enclosures);
    Ok(ArticleSummary {
        id: entry.id,
        feed_id: entry.feed_id,
        category_id,
        feed_title: feed.title,
        title: entry.title,
        url: entry.url,
        comments_url: entry.comments_url,
        published_at: published
            .to_utc()
            .to_rfc3339_opts(SecondsFormat::Secs, true),
        is_read: entry.status == "read",
        is_starred: entry.starred,
        reading_time_minutes: entry.reading_time,
        preview: processed.preview,
        image_url: processed.image_url,
    })
}

fn map_enclosures(
    article_id: i64,
    enclosures: Vec<EnclosureDto>,
) -> Result<Vec<Enclosure>, CoreError> {
    enclosures
        .into_iter()
        .map(|enclosure| {
            if enclosure.entry_id != article_id {
                return Err(CoreError::data(format!(
                    "enclosure {} references article {} instead of {}",
                    enclosure.id, enclosure.entry_id, article_id
                )));
            }
            Ok(Enclosure {
                id: enclosure.id,
                article_id,
                url: enclosure.url,
                mime_type: enclosure.mime_type,
                size_bytes: (enclosure.size > 0).then_some(enclosure.size as u64),
                remote_media_progression_seconds: enclosure.media_progression,
            })
        })
        .collect()
}
fn entry_to_saved_media_article(entry: EntryDto) -> Result<RemoteSavedMediaArticle, CoreError> {
    let published = DateTime::parse_from_rfc3339(&entry.published_at).map_err(|_| {
        CoreError::data(format!("article {} has invalid publication time", entry.id))
    })?;
    let enclosures = map_enclosures(entry.id, entry.enclosures)?;
    let enclosure_inputs = enclosures
        .iter()
        .map(|item| crate::article::EnclosureInput {
            url: item.url.clone(),
            mime_type: item.mime_type.clone(),
        })
        .collect::<Vec<_>>();
    let processed = crate::article::process(&entry.content, &entry.url, &enclosure_inputs);
    Ok(RemoteSavedMediaArticle {
        article: Article {
            id: entry.id,
            feed_id: entry.feed_id,
            title: entry.title,
            url: entry.url,
            comments_url: entry.comments_url,
            published_at: published
                .to_utc()
                .to_rfc3339_opts(SecondsFormat::Secs, true),
            is_read: entry.status == "read",
            is_starred: entry.starred,
            raw_html_content: entry.content,
            reading_time_minutes: entry.reading_time,
            preview: processed.preview,
            image_url: processed.image_url,
        },
        enclosures,
    })
}
#[derive(Deserialize)]
struct CategoryRefDto {
    id: i64,
}
#[derive(Deserialize)]
struct IconDto {
    #[serde(default)]
    data: Option<String>,
    #[serde(default)]
    mime_type: Option<String>,
}
#[derive(Deserialize)]
struct ErrorDto {
    #[serde(default)]
    error_message: String,
}
#[derive(Deserialize)]
struct CreateFeedDto {
    feed_id: i64,
}
#[derive(Deserialize)]
struct CreateCategoryDto {
    id: i64,
}
#[derive(Deserialize)]
struct DiscoveredSubscriptionDto {
    #[serde(default)]
    url: String,
    #[serde(default)]
    title: String,
    #[serde(rename = "type", default)]
    feed_type: String,
}

fn discovery_request_json(request: DiscoverSubscriptionsRequest) -> serde_json::Value {
    let mut body = serde_json::Map::new();
    body.insert("url".into(), request.url.into());
    insert_optional_string(&mut body, "username", request.username);
    insert_optional_string(&mut body, "password", request.password);
    insert_optional_string(&mut body, "user_agent", request.user_agent);
    insert_optional_bool(&mut body, "fetch_via_proxy", request.fetch_via_proxy);
    body.into()
}

fn create_feed_request_json(request: CreateFeedRequest) -> serde_json::Value {
    let mut body = serde_json::Map::new();
    body.insert("feed_url".into(), request.feed_url.into());
    if let Some(category_id) = request.category_id {
        body.insert("category_id".into(), category_id.into());
    }
    insert_optional_string(&mut body, "username", request.username);
    insert_optional_string(&mut body, "password", request.password);
    insert_optional_bool(&mut body, "crawler", request.crawler);
    insert_optional_string(&mut body, "user_agent", request.user_agent);
    insert_optional_string(&mut body, "scraper_rules", request.scraper_rules);
    insert_optional_string(&mut body, "rewrite_rules", request.rewrite_rules);
    insert_optional_string(&mut body, "blocklist_rules", request.blocklist_rules);
    insert_optional_string(&mut body, "keeplist_rules", request.keeplist_rules);
    insert_optional_bool(&mut body, "disabled", request.disabled);
    insert_optional_bool(&mut body, "ignore_http_cache", request.ignore_http_cache);
    insert_optional_bool(&mut body, "fetch_via_proxy", request.fetch_via_proxy);
    body.into()
}

fn insert_optional_string(
    body: &mut serde_json::Map<String, serde_json::Value>,
    key: &str,
    value: Option<String>,
) {
    if let Some(value) = value {
        body.insert(key.into(), value.into());
    }
}

fn insert_optional_bool(
    body: &mut serde_json::Map<String, serde_json::Value>,
    key: &str,
    value: Option<bool>,
) {
    if let Some(value) = value {
        body.insert(key.into(), value.into());
    }
}
impl IconDto {
    fn data_url(self) -> Option<String> {
        let data = self.data?.trim().to_string();
        if data.is_empty() {
            None
        } else if data.starts_with("data:") {
            Some(data)
        } else if data.starts_with("image/") {
            Some(format!("data:{data}"))
        } else if self
            .mime_type
            .as_deref()
            .is_some_and(|mime| mime.starts_with("image/"))
        {
            Some(format!("data:{};base64,{data}", self.mime_type.unwrap()))
        } else {
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn entry_reading_time_reaches_article_summary() {
        let entry: EntryDto = serde_json::from_str(
            r#"{
                "id": 42,
                "feed_id": 7,
                "published_at": "2026-09-20T12:00:00Z",
                "reading_time": 6,
                "feed": {
                    "id": 7,
                    "title": "Example Feed",
                    "feed_url": "https://example.test/feed",
                    "disabled": false,
                    "category": { "id": 3 }
                }
            }"#,
        )
        .unwrap();

        let summary = search_article_summary(entry).unwrap();
        assert_eq!(summary.reading_time_minutes, 6);
    }
    use std::io::{BufRead, BufReader, Read, Write};
    use std::net::{SocketAddr, TcpListener};
    use std::thread;

    fn version_server(
        status: u16,
        body: &'static str,
    ) -> (SocketAddr, thread::JoinHandle<(String, bool)>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let worker = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut request = String::new();
            reader.read_line(&mut request).unwrap();
            let target = request.split_whitespace().nth(1).unwrap().to_string();
            let mut authenticated = false;
            let mut content_length = 0usize;
            loop {
                request.clear();
                reader.read_line(&mut request).unwrap();
                if request == "\r\n" {
                    break;
                }
                let lower = request.to_ascii_lowercase();
                authenticated |= lower.starts_with("x-auth-token: test-key");
                if let Some(value) = lower.strip_prefix("content-length:") {
                    content_length = value.trim().parse().unwrap();
                }
            }
            if content_length > 0 {
                let mut request_body = vec![0; content_length];
                reader.read_exact(&mut request_body).unwrap();
            }
            write!(stream, "HTTP/1.1 {status} Test\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len()).unwrap();
            (target, authenticated)
        });
        (address, worker)
    }

    fn header_server(body: &'static str) -> (SocketAddr, thread::JoinHandle<Vec<String>>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let worker = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut headers = Vec::new();
            let mut line = String::new();
            reader.read_line(&mut line).unwrap();
            loop {
                line.clear();
                reader.read_line(&mut line).unwrap();
                if line == "\r\n" {
                    break;
                }
                headers.push(line.trim().to_ascii_lowercase());
            }
            write!(stream, "HTTP/1.1 200 Test\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len()).unwrap();
            headers
        });
        (address, worker)
    }

    #[test]
    fn normalizes_installation_urls_and_rejects_non_base_components() {
        for (input, expected) in [
            ("https://example.com", "https://example.com"),
            ("https://example.com/", "https://example.com"),
            ("https://example.com/v1", "https://example.com"),
            ("https://example.com/v1/", "https://example.com"),
            (
                "https://example.com/miniflux",
                "https://example.com/miniflux",
            ),
            (
                "https://example.com/miniflux/",
                "https://example.com/miniflux",
            ),
            (
                "https://example.com/miniflux/v1",
                "https://example.com/miniflux",
            ),
            (
                "https://example.com/miniflux/v1/",
                "https://example.com/miniflux",
            ),
            (
                "https://example.com/foo/bar/v1",
                "https://example.com/foo/bar",
            ),
            (
                "https://example.com/v1/miniflux",
                "https://example.com/v1/miniflux",
            ),
            (
                "https://example.com:8443/miniflux",
                "https://example.com:8443/miniflux",
            ),
            ("http://example.com/miniflux", "http://example.com/miniflux"),
        ] {
            assert_eq!(normalize_installation_base(input).unwrap(), expected);
        }
        assert_eq!(
            normalize_installation_base("ftp://example.com").unwrap_err(),
            AccountValidationError::UnsupportedUrlScheme
        );
        for input in [
            "not a URL",
            "https://example.com/miniflux?next=/v1",
            "https://example.com/miniflux#settings",
        ] {
            assert_eq!(
                normalize_installation_base(input).unwrap_err(),
                AccountValidationError::InvalidUrl
            );
        }
    }

    #[test]
    fn media_progress_http_errors_retain_status_for_delivery_and_diagnostics() {
        let (address, worker) = version_server(404, "");
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        let error = client.set_media_progression(15986615, 12).unwrap_err();

        assert_eq!(
            error.kind,
            crate::domain::CoreErrorKind::InvalidConfiguration
        );
        assert_eq!(error.http_status(), Some(404));
        assert_eq!(worker.join().unwrap().0, "/v1/enclosures/15986615");
    }

    #[test]
    fn builds_api_and_web_routes_from_installation_base() {
        let root = MinifluxClient::new("https://example.com", "test-key").unwrap();
        assert_eq!(
            root.api_url("/v1/version"),
            "https://example.com/v1/version"
        );
        assert_eq!(
            root.api_url("/v1/entries"),
            "https://example.com/v1/entries"
        );
        assert_eq!(
            miniflux_entry_url(root.installation_base(), 583862),
            "https://example.com/unread/entry/583862"
        );

        let subpath = MinifluxClient::new("https://example.com/miniflux/v1", "test-key").unwrap();
        assert_eq!(
            subpath.api_url("/v1/version"),
            "https://example.com/miniflux/v1/version"
        );
        assert_eq!(
            subpath.api_url("/v1/entries"),
            "https://example.com/miniflux/v1/entries"
        );
        assert_eq!(
            miniflux_entry_url(subpath.installation_base(), 583862),
            "https://example.com/miniflux/unread/entry/583862"
        );
    }

    #[test]
    fn validates_candidate_account_without_configuration_mutation() {
        let (address, worker) = version_server(200, r#"{"version":"2.0.49","commit":"abc"}"#);
        let result =
            MinifluxClient::validate_account(&format!("http://{address}/v1"), "test-key", vec![])
                .unwrap();
        assert_eq!(result.installation_base, format!("http://{address}"));
        assert_eq!(result.version, "2.0.49");
        assert_eq!(worker.join().unwrap(), ("/v1/version".into(), true));
        assert_eq!(result.capabilities(), Vec::<MinifluxCapability>::new());

        let (address, worker) = version_server(200, r#"{"version":"2.0.50"}"#);
        let result = MinifluxClient::validate_account(
            &format!("http://{address}/miniflux"),
            "test-key",
            vec![],
        )
        .unwrap();
        assert_eq!(
            result.installation_base,
            format!("http://{address}/miniflux")
        );
        assert_eq!(
            worker.join().unwrap(),
            ("/miniflux/v1/version".into(), true)
        );
    }

    #[test]
    fn derives_media_sync_capabilities_from_supported_versions() {
        assert_eq!(
            MinifluxCapability::all_supported_by("2.2.0"),
            vec![MinifluxCapability::MediaProgressSync]
        );
        assert_eq!(
            MinifluxCapability::all_supported_by("2.2.15"),
            vec![MinifluxCapability::MediaProgressSync]
        );
        assert_eq!(
            MinifluxCapability::all_supported_by("2.2.16"),
            vec![
                MinifluxCapability::MediaProgressSync,
                MinifluxCapability::SavedMediaSync
            ]
        );
        assert_eq!(
            MinifluxCapability::all_supported_by("v2.3.1"),
            vec![
                MinifluxCapability::MediaProgressSync,
                MinifluxCapability::SavedMediaSync
            ]
        );
        assert!(MinifluxCapability::all_supported_by("2.1.9").is_empty());
        assert!(MinifluxCapability::all_supported_by("invalid").is_empty());
    }

    #[test]
    fn validation_maps_auth_endpoint_and_response_failures() {
        for (status, expected) in [
            (401, AccountValidationError::Unauthorized),
            (403, AccountValidationError::Unauthorized),
            (404, AccountValidationError::IncompatibleServer),
        ] {
            let (address, worker) = version_server(status, "");
            assert_eq!(
                MinifluxClient::validate_account(&format!("http://{address}"), "test-key", vec![])
                    .unwrap_err(),
                expected
            );
            worker.join().unwrap();
        }
        for body in ["not JSON", r#"{}"#, r#"{"version":""}"#] {
            let (address, worker) = version_server(200, body);
            assert_eq!(
                MinifluxClient::validate_account(&format!("http://{address}"), "test-key", vec![])
                    .unwrap_err(),
                AccountValidationError::InvalidResponse
            );
            worker.join().unwrap();
        }
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        drop(listener);
        assert_eq!(
            MinifluxClient::validate_account(&format!("http://{address}"), "test-key", vec![])
                .unwrap_err(),
            AccountValidationError::Network
        );
    }

    #[test]
    fn validation_diagnostic_preserves_network_category_and_redacts_secrets() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        drop(listener);
        let api_key = "validation-api-key";
        let header_value = "validation-header-value";
        let attempt = MinifluxClient::validate_account_with_diagnostic(
            &format!("http://{address}"),
            api_key,
            vec![HttpHeader {
                name: "X-Diagnostic".into(),
                value: header_value.into(),
            }],
        );

        assert_eq!(attempt.result, None);
        assert_eq!(attempt.error, Some(AccountValidationError::Network));
        let diagnostic = attempt.diagnostic.expect("transport diagnostic");
        assert!(!diagnostic.category.is_empty());
        assert!(!diagnostic.detail.is_empty());
        assert!(!diagnostic.detail.contains(api_key));
        assert!(!diagnostic.detail.contains(header_value));
    }

    #[test]
    fn successful_validation_has_no_diagnostic() {
        let (address, worker) = version_server(200, r#"{"version":"2.0.50"}"#);
        let attempt = MinifluxClient::validate_account_with_diagnostic(
            &format!("http://{address}"),
            "test-key",
            vec![],
        );

        assert!(attempt.error.is_none());
        assert!(attempt.diagnostic.is_none());
        assert_eq!(attempt.result.unwrap().version, "2.0.50");
        worker.join().unwrap();
    }

    #[test]
    fn custom_headers_are_applied_to_miniflux_requests_and_validation() {
        let headers = vec![HttpHeader {
            name: "X-Proxy-Route".into(),
            value: "account-route".into(),
        }];
        let (address, worker) = header_server(r#"{"version":"2.0.50"}"#);
        MinifluxClient::validate_account(&format!("http://{address}"), "test-key", headers.clone())
            .unwrap();
        assert!(
            worker
                .join()
                .unwrap()
                .iter()
                .any(|header| header == "x-proxy-route: account-route")
        );

        let (address, worker) = header_server(r#"{"total":0,"entries":[]}"#);
        let client =
            MinifluxClient::new_with_headers(&format!("http://{address}"), "test-key", headers)
                .unwrap();
        let _: EntriesDto = client.get("/v1/entries", &[]).unwrap();
        assert!(
            worker
                .join()
                .unwrap()
                .iter()
                .any(|header| header == "x-proxy-route: account-route")
        );
    }

    #[test]
    fn custom_headers_are_not_sent_to_external_images() {
        let (address, worker) = header_server("image");
        let client = MinifluxClient::new_with_headers(
            "https://miniflux.example",
            "test-key",
            vec![HttpHeader {
                name: "X-Proxy-Route".into(),
                value: "account-route".into(),
            }],
        )
        .unwrap();
        client
            .download_image(&format!("http://{address}/image"), 1024)
            .unwrap();
        assert!(
            worker
                .join()
                .unwrap()
                .iter()
                .all(|header| !header.starts_with("x-proxy-route:"))
        );
    }

    #[test]
    fn custom_header_validation_is_case_insensitive_and_redacts_values() {
        // Flux uses X-Auth-Token for Miniflux authentication; it must not be
        // replaceable by a custom header. Authorization is intentionally
        // allowed so users can provide reverse-proxy Basic/Bearer credentials.
        for protected_name in ["X-Auth-Token", "x-auth-token", "CONTENT-TYPE"] {
            assert_eq!(
                validate_custom_headers(&[HttpHeader {
                    name: protected_name.into(),
                    value: "secret-value".into(),
                }]),
                Err(AccountValidationError::InvalidCustomHeader),
                "{} should be protected",
                protected_name
            );
        }
        assert!(
            validate_custom_headers(&[HttpHeader {
                name: "Authorization".into(),
                value: "Bearer abc".into(),
            }])
            .is_ok(),
            "Authorization should be allowed as a custom header"
        );
        assert!(
            validate_custom_headers(&[HttpHeader {
                name: "authorization".into(),
                value: "Basic dXNlcjpwYXNz".into(),
            }])
            .is_ok(),
            "Authorization should be allowed case-insensitively"
        );
        assert_eq!(
            validate_custom_headers(&[
                HttpHeader {
                    name: "X-Route".into(),
                    value: "one".into()
                },
                HttpHeader {
                    name: "x-route".into(),
                    value: "two".into()
                },
            ]),
            Err(AccountValidationError::InvalidCustomHeader)
        );
        assert!(
            !format!(
                "{:?}",
                HttpHeader {
                    name: "X-Route".into(),
                    value: "secret-value".into()
                }
            )
            .contains("secret-value")
        );
    }

    fn entry_page(total: i64, ids: impl IntoIterator<Item = i64>) -> String {
        let entries = ids
            .into_iter()
            .map(|id| {
                serde_json::json!({
                    "id": id,
                    "feed_id": 1,
                    "published_at": "2026-01-02T03:04:05Z",
                })
            })
            .collect::<Vec<_>>();
        serde_json::json!({ "total": total, "entries": entries }).to_string()
    }

    fn entry_server(
        responses: Vec<(u16, String)>,
    ) -> (SocketAddr, thread::JoinHandle<Vec<String>>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let worker = thread::spawn(move || {
            let mut targets = Vec::new();
            for (status, body) in responses {
                let (mut stream, _) = listener.accept().unwrap();
                let mut reader = BufReader::new(stream.try_clone().unwrap());
                let mut line = String::new();
                reader.read_line(&mut line).unwrap();
                targets.push(line.split_whitespace().nth(1).unwrap().to_string());
                let mut authenticated = false;
                loop {
                    line.clear();
                    reader.read_line(&mut line).unwrap();
                    if line == "\r\n" {
                        break;
                    }
                    if line
                        .to_ascii_lowercase()
                        .starts_with("x-auth-token: test-key")
                    {
                        authenticated = true;
                    }
                }
                assert!(authenticated);
                write!(stream, "HTTP/1.1 {status} Test\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body).unwrap();
            }
            targets
        });
        (address, worker)
    }

    type JsonRequest = (String, String, serde_json::Value);
    type JsonServer = (SocketAddr, thread::JoinHandle<Vec<JsonRequest>>);

    fn json_server(responses: Vec<(u16, String)>) -> JsonServer {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let worker = thread::spawn(move || {
            let mut requests = Vec::new();
            for (status, body) in responses {
                let (mut stream, _) = listener.accept().unwrap();
                let mut reader = BufReader::new(stream.try_clone().unwrap());
                let mut request_line = String::new();
                reader.read_line(&mut request_line).unwrap();
                let mut content_length = 0;
                loop {
                    let mut header = String::new();
                    reader.read_line(&mut header).unwrap();
                    if header == "\r\n" {
                        break;
                    }
                    if let Some((name, value)) = header.split_once(':')
                        && name.eq_ignore_ascii_case("Content-Length")
                    {
                        content_length = value.trim().parse().unwrap();
                    }
                }
                let mut request_body = vec![0; content_length];
                std::io::Read::read_exact(&mut reader, &mut request_body).unwrap();
                let mut parts = request_line.split_whitespace();
                requests.push((
                    parts.next().unwrap().into(),
                    parts.next().unwrap().into(),
                    serde_json::from_slice(&request_body).unwrap(),
                ));
                write!(stream, "HTTP/1.1 {status} Test\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body).unwrap();
            }
            requests
        });
        (address, worker)
    }

    fn unread_entry_targets(after_ids: &[i64]) -> Vec<String> {
        let mut targets =
            vec!["/v1/entries?limit=100&order=id&direction=asc&status=unread".to_string()];
        targets.extend(after_ids.iter().map(|id| {
            format!(
                "/v1/entries?limit=100&order=id&direction=asc&status=unread&after_entry_id={id}"
            )
        }));
        targets
    }

    fn marker_page(status: &str, ids: impl IntoIterator<Item = i64>) -> String {
        serde_json::json!({
            "entries": ids.into_iter().map(|id| serde_json::json!({
                "id": id,
                "feed_id": 77,
                "status": status,
                "external_id": format!("flux:saved-media:v1:{}:{}", id, id),
                "published_at": "2026-01-02T03:04:05Z",
            })).collect::<Vec<_>>(),
        })
        .to_string()
    }

    #[test]
    fn entries_continue_after_decreasing_totals_until_empty_page() {
        let (address, worker) = entry_server(vec![
            (200, entry_page(230, 1..=100)),
            (200, entry_page(130, 101..=200)),
            (200, entry_page(30, 201..=230)),
            (200, entry_page(0, [])),
        ]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        let entries = client.entries(Some("unread"), false).unwrap();

        assert_eq!(
            entries
                .into_iter()
                .map(|entry| entry.id)
                .collect::<Vec<_>>(),
            (1..=230).collect::<Vec<_>>()
        );
        assert_eq!(
            worker.join().unwrap(),
            unread_entry_targets(&[100, 200, 230])
        );
    }

    #[test]
    fn entries_fetch_empty_page_after_exactly_full_page() {
        let (address, worker) = entry_server(vec![
            (200, entry_page(100, 1..=100)),
            (200, entry_page(0, [])),
        ]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        let entries = client.entries(Some("unread"), false).unwrap();

        assert_eq!(entries.len(), 100);
        assert_eq!(worker.join().unwrap(), unread_entry_targets(&[100]));
    }

    #[test]
    fn saved_media_markers_paginate_every_status() {
        let (address, worker) = entry_server(vec![
            (200, marker_page("unread", 1..=100)),
            (200, marker_page("unread", [101])),
            (200, marker_page("unread", [])),
            (200, marker_page("read", [102])),
            (200, marker_page("read", [])),
            (200, marker_page("removed", 103..=202)),
            (200, marker_page("removed", [203])),
            (200, marker_page("removed", [])),
        ]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        let markers = client.saved_media_markers(77).unwrap();

        assert_eq!(markers.len(), 203);
        assert!(markers.iter().any(|marker| marker.entry_id == 101));
        assert!(markers.iter().any(|marker| marker.entry_id == 102));
        assert!(markers.iter().any(|marker| marker.entry_id == 203));
        assert_eq!(
            worker.join().unwrap(),
            vec![
                "/v1/entries?feed_id=77&status=unread&limit=100&order=id&direction=asc",
                "/v1/entries?feed_id=77&status=unread&limit=100&order=id&direction=asc&after_entry_id=100",
                "/v1/entries?feed_id=77&status=unread&limit=100&order=id&direction=asc&after_entry_id=101",
                "/v1/entries?feed_id=77&status=read&limit=100&order=id&direction=asc",
                "/v1/entries?feed_id=77&status=read&limit=100&order=id&direction=asc&after_entry_id=102",
                "/v1/entries?feed_id=77&status=removed&limit=100&order=id&direction=asc",
                "/v1/entries?feed_id=77&status=removed&limit=100&order=id&direction=asc&after_entry_id=202",
                "/v1/entries?feed_id=77&status=removed&limit=100&order=id&direction=asc&after_entry_id=203",
            ]
        );
    }

    #[test]
    fn entries_accept_empty_first_page() {
        let (address, worker) = entry_server(vec![(200, entry_page(0, []))]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        assert!(client.entries(Some("unread"), false).unwrap().is_empty());
        assert_eq!(worker.join().unwrap(), unread_entry_targets(&[]));
    }

    #[test]
    fn entries_reject_unstable_later_page() {
        let (address, worker) = entry_server(vec![
            (200, entry_page(100, 1..=100)),
            (200, entry_page(1, [100])),
        ]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        let error = match client.entries(Some("unread"), false) {
            Err(error) => error,
            Ok(_) => panic!("unstable entry pagination should fail"),
        };

        assert_eq!(error.kind, crate::domain::CoreErrorKind::Data);
        assert_eq!(error.message, "Miniflux returned unstable entry pagination");
        assert_eq!(worker.join().unwrap(), unread_entry_targets(&[100]));
    }

    #[test]
    fn entries_return_error_when_second_page_fails() {
        let (address, worker) =
            entry_server(vec![(200, entry_page(100, 1..=100)), (500, String::new())]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        let error = match client.entries(Some("unread"), false) {
            Err(error) => error,
            Ok(_) => panic!("second-page server failure should fail entry fetch"),
        };

        assert_eq!(error.kind, crate::domain::CoreErrorKind::ServerTransient);
        assert_eq!(error.message, "Miniflux server returned HTTP 500");
        assert_eq!(worker.join().unwrap(), unread_entry_targets(&[100]));
    }

    #[test]
    fn search_encodes_parameters_and_processes_temporary_results() {
        let response = r#"{"total":7,"entries":[{"id":42,"feed_id":9,"feed":{"id":9,"title":"Engineering","category":{"id":3}},"title":"Rust & Systems","url":"https://example.test/posts/42","comments_url":"https://example.test/comments/42","status":"read","starred":true,"published_at":"2026-01-02T03:04:05+02:00","content":"<p>source &amp; preview</p><img src=\"/cover.jpg\">"}]}"#;
        let (address, worker) = entry_server(vec![(200, response.into())]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        let result = client
            .search_articles(SearchArticlesRequest {
                query: "rust & systems".into(),
                offset: 20,
                limit: 10,
            })
            .unwrap();

        assert_eq!(result.total, 7);
        assert_eq!(result.articles.len(), 1);
        let article = &result.articles[0];
        assert_eq!(article.feed_title, "Engineering");
        assert_eq!(article.category_id, 3);
        assert_eq!(article.preview, "source & preview");
        assert_eq!(
            article.image_url.as_deref(),
            Some("https://example.test/cover.jpg")
        );
        assert_eq!(article.published_at, "2026-01-02T01:04:05Z");
        assert!(article.is_read);
        assert!(article.is_starred);
        assert_eq!(
            worker.join().unwrap(),
            vec![
                "/v1/entries?search=rust+%26+systems&order=published_at&direction=desc&offset=20&limit=10"
            ]
        );
    }

    #[test]
    fn search_accepts_empty_results_and_propagates_failure() {
        let (address, worker) = entry_server(vec![(200, r#"{"total":0,"entries":[]}"#.into())]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();
        let result = client
            .search_articles(SearchArticlesRequest {
                query: "none".into(),
                offset: 0,
                limit: 50,
            })
            .unwrap();
        assert_eq!(result.total, 0);
        assert!(result.articles.is_empty());
        worker.join().unwrap();

        let (address, worker) = entry_server(vec![(500, String::new())]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();
        let error = client
            .search_articles(SearchArticlesRequest {
                query: "failure".into(),
                offset: 0,
                limit: 1,
            })
            .unwrap_err();
        assert_eq!(error.kind, crate::domain::CoreErrorKind::ServerTransient);
        worker.join().unwrap();
    }

    #[test]
    fn set_starred_state_changes_only_when_needed_and_propagates_errors() {
        let (address, worker) = entry_server(vec![
            (
                200,
                r#"{"id":42,"feed_id":9,"starred":false,"published_at":"2026-01-02T03:04:05Z"}"#
                    .into(),
            ),
            (204, String::new()),
            (
                200,
                r#"{"id":42,"feed_id":9,"starred":true,"published_at":"2026-01-02T03:04:05Z"}"#
                    .into(),
            ),
            (204, String::new()),
        ]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();
        client.set_starred_state(42, true).unwrap();
        client.set_starred_state(42, false).unwrap();
        assert_eq!(
            worker.join().unwrap(),
            vec![
                "/v1/entries/42",
                "/v1/entries/42/star",
                "/v1/entries/42",
                "/v1/entries/42/star",
            ]
        );

        let (address, worker) = entry_server(vec![(500, String::new())]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();
        let error = client.set_starred_state(42, true).unwrap_err();
        assert_eq!(error.kind, crate::domain::CoreErrorKind::ServerTransient);
        worker.join().unwrap();
    }

    #[test]
    fn set_read_state_sends_direct_remote_update() {
        let (address, worker) = json_server(vec![(204, String::new())]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();
        client.set_read_state(&[42], true).unwrap();
        assert_eq!(
            worker.join().unwrap(),
            vec![(
                "PUT".into(),
                "/v1/entries".into(),
                serde_json::json!({"entry_ids": [42], "status": "read"}),
            )]
        );
    }

    #[test]
    fn save_to_service_accepts_202() {
        let (address, worker) = entry_server(vec![(202, String::new())]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        assert_eq!(
            client.save_to_service(42).unwrap(),
            SaveToServiceResult::Saved
        );
        assert_eq!(worker.join().unwrap(), vec!["/v1/entries/42/save"]);
    }

    #[test]
    fn save_to_service_reports_missing_integration() {
        let (address, worker) = entry_server(vec![(
            400,
            r#"{"error_message":"no third-party integration enabled"}"#.into(),
        )]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        assert_eq!(
            client.save_to_service(42).unwrap(),
            SaveToServiceResult::NoIntegrationConfigured
        );
        assert_eq!(worker.join().unwrap(), vec!["/v1/entries/42/save"]);
    }

    #[test]
    fn save_to_service_reports_unexpected_server_failure() {
        let (address, worker) = entry_server(vec![(500, String::new())]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        let error = client.save_to_service(42).unwrap_err();

        assert_eq!(error.kind, crate::domain::CoreErrorKind::ServerTransient);
        assert_eq!(error.message, "Miniflux server returned HTTP 500");
        assert_eq!(worker.join().unwrap(), vec!["/v1/entries/42/save"]);
    }

    #[test]
    fn create_feed_sends_only_the_required_field_when_options_are_omitted() {
        let (address, worker) = json_server(vec![(201, r#"{"feed_id":42}"#.into())]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        assert_eq!(
            client
                .create_feed(CreateFeedRequest {
                    feed_url: "https://example.test/feed.xml".into(),
                    category_id: None,
                    username: None,
                    password: None,
                    crawler: None,
                    user_agent: None,
                    scraper_rules: None,
                    rewrite_rules: None,
                    blocklist_rules: None,
                    keeplist_rules: None,
                    disabled: None,
                    ignore_http_cache: None,
                    fetch_via_proxy: None,
                })
                .unwrap(),
            CreateFeedResult { feed_id: 42 }
        );
        assert_eq!(
            worker.join().unwrap(),
            vec![(
                "POST".into(),
                "/v1/feeds".into(),
                serde_json::json!({"feed_url": "https://example.test/feed.xml"}),
            )]
        );
    }

    #[test]
    fn create_feed_preserves_all_supplied_optional_fields() {
        let (address, worker) = json_server(vec![(201, r#"{"feed_id":43}"#.into())]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        client
            .create_feed(CreateFeedRequest {
                feed_url: "https://example.test/feed.xml".into(),
                category_id: Some(7),
                username: Some("feed-user".into()),
                password: Some("feed-password".into()),
                crawler: Some(false),
                user_agent: Some("Flux Test".into()),
                scraper_rules: Some("article".into()),
                rewrite_rules: Some("replace".into()),
                blocklist_rules: Some("ads".into()),
                keeplist_rules: Some("main".into()),
                disabled: Some(false),
                ignore_http_cache: Some(true),
                fetch_via_proxy: Some(false),
            })
            .unwrap();

        assert_eq!(
            worker.join().unwrap()[0].2,
            serde_json::json!({
                "feed_url": "https://example.test/feed.xml",
                "category_id": 7,
                "username": "feed-user",
                "password": "feed-password",
                "crawler": false,
                "user_agent": "Flux Test",
                "scraper_rules": "article",
                "rewrite_rules": "replace",
                "blocklist_rules": "ads",
                "keeplist_rules": "main",
                "disabled": false,
                "ignore_http_cache": true,
                "fetch_via_proxy": false,
            })
        );
    }

    #[test]
    fn create_feed_reports_server_failures() {
        let (address, worker) = json_server(vec![(500, String::new())]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        let error = client
            .create_feed(CreateFeedRequest {
                feed_url: "https://example.test/feed.xml".into(),
                category_id: None,
                username: None,
                password: None,
                crawler: None,
                user_agent: None,
                scraper_rules: None,
                rewrite_rules: None,
                blocklist_rules: None,
                keeplist_rules: None,
                disabled: None,
                ignore_http_cache: None,
                fetch_via_proxy: None,
            })
            .unwrap_err();

        assert_eq!(error.kind, crate::domain::CoreErrorKind::ServerTransient);
        assert_eq!(worker.join().unwrap()[0].1, "/v1/feeds");
    }

    #[test]
    fn create_category_sends_title_and_maps_created_identity() {
        let (address, worker) = json_server(vec![(
            201,
            r#"{"id":44,"title":"Engineering","user_id":1}"#.into(),
        )]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        assert_eq!(
            client.create_category("Engineering".into()).unwrap(),
            CreateCategoryResult { category_id: 44 }
        );
        assert_eq!(
            worker.join().unwrap(),
            vec![(
                "POST".into(),
                "/v1/categories".into(),
                serde_json::json!({"title": "Engineering"}),
            )]
        );
    }

    #[test]
    fn create_category_reports_server_failures() {
        let (address, worker) = json_server(vec![(500, String::new())]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        let error = client.create_category("Engineering".into()).unwrap_err();

        assert_eq!(error.kind, crate::domain::CoreErrorKind::ServerTransient);
        assert_eq!(worker.join().unwrap()[0].1, "/v1/categories");
    }

    #[test]
    fn discovery_returns_multiple_candidates() {
        let response = r#"[{"url":"https://example.test/atom","title":"Atom","type":"atom"},{"url":"https://example.test/rss","title":"RSS","type":"rss"}]"#;
        let (address, worker) = json_server(vec![(200, response.into())]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        assert_eq!(
            client
                .discover_subscriptions(DiscoverSubscriptionsRequest {
                    url: "https://example.test".into(),
                    username: Some("feed-user".into()),
                    password: Some("feed-password".into()),
                    user_agent: Some("Flux Test".into()),
                    fetch_via_proxy: Some(false),
                })
                .unwrap(),
            vec![
                DiscoveredSubscription {
                    url: "https://example.test/atom".into(),
                    title: "Atom".into(),
                    feed_type: "atom".into()
                },
                DiscoveredSubscription {
                    url: "https://example.test/rss".into(),
                    title: "RSS".into(),
                    feed_type: "rss".into()
                },
            ]
        );
        assert_eq!(
            worker.join().unwrap()[0],
            (
                "POST".into(),
                "/v1/discover".into(),
                serde_json::json!({
                    "url": "https://example.test",
                    "username": "feed-user",
                    "password": "feed-password",
                    "user_agent": "Flux Test",
                    "fetch_via_proxy": false,
                }),
            )
        );
    }

    #[test]
    fn discovery_accepts_no_candidates() {
        let (address, worker) = json_server(vec![(200, "[]".into())]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        assert!(
            client
                .discover_subscriptions(DiscoverSubscriptionsRequest {
                    url: "https://example.test".into(),
                    username: None,
                    password: None,
                    user_agent: None,
                    fetch_via_proxy: None,
                })
                .unwrap()
                .is_empty()
        );
        assert_eq!(worker.join().unwrap()[0].1, "/v1/discover");
    }

    #[test]
    fn discovery_reports_server_failures() {
        let (address, worker) = json_server(vec![(500, String::new())]);
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        let error = client
            .discover_subscriptions(DiscoverSubscriptionsRequest {
                url: "https://example.test".into(),
                username: None,
                password: None,
                user_agent: None,
                fetch_via_proxy: None,
            })
            .unwrap_err();

        assert_eq!(error.kind, crate::domain::CoreErrorKind::ServerTransient);
        assert_eq!(worker.join().unwrap()[0].1, "/v1/discover");
    }

    #[test]
    fn cancellable_entry_pagination_does_not_start_another_page_after_cancel() {
        let cancellation = SyncCancellation::new();
        let worker_cancellation = cancellation.clone();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let worker = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut line = String::new();
            reader.read_line(&mut line).unwrap();
            assert!(line.contains("/v1/entries"));
            loop {
                line.clear();
                reader.read_line(&mut line).unwrap();
                if line == "\r\n" {
                    break;
                }
            }
            let body = r#"{"total":2,"entries":[{"id":4,"feed_id":9,"title":"First page","url":"https://entry/post","status":"unread","starred":false,"published_at":"2026-01-02T03:04:05Z","content":"<p>preview</p>","enclosures":[]}]}"#;
            worker_cancellation.cancel();
            write!(stream, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body).unwrap();
            thread::sleep(std::time::Duration::from_millis(50));
            listener.set_nonblocking(true).unwrap();
            assert!(
                listener.accept().is_err(),
                "cancellation must prevent the next page request"
            );
        });
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();

        assert!(
            client
                .entries_with_cancellation(Some("unread"), false, Some(&cancellation))
                .unwrap()
                .is_none()
        );
        worker.join().unwrap();
    }

    #[test]
    fn fetches_only_unread_and_starred_entries_without_read_history() {
        let responses = vec![
            r#"[{"id":1,"title":"Category"}]"#,
            r#"[{"id":9,"title":"Feed","category":{"id":1}}]"#,
            r#"{"total":1,"entries":[{"id":4,"feed_id":9,"title":"Unread and starred","url":"https://entry/post","status":"unread","starred":true,"published_at":"2026-01-02T03:04:05Z","content":"<p>source &amp; preview</p>","enclosures":[{"id":40,"entry_id":4,"url":"audio.mp3","mime_type":"audio/mpeg"},{"id":41,"entry_id":4,"url":"/cover.jpg","mime_type":"image/jpeg"}]}]}"#,
            r#"{"total":0,"entries":[]}"#,
            r#"{"total":1,"entries":[{"id":4,"feed_id":9,"title":"Unread and starred","url":"https://entry/post","status":"unread","starred":true,"published_at":"2026-01-02T03:04:05Z","content":"<p>source &amp; preview</p>","enclosures":[{"id":40,"entry_id":4,"url":"audio.mp3","mime_type":"audio/mpeg"},{"id":41,"entry_id":4,"url":"/cover.jpg","mime_type":"image/jpeg"}]}]}"#,
            r#"{"total":0,"entries":[]}"#,
        ];
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let worker = thread::spawn(move || {
            let mut targets = Vec::new();
            for body in responses {
                let (mut stream, _) = listener.accept().unwrap();
                let mut reader = BufReader::new(stream.try_clone().unwrap());
                let mut line = String::new();
                reader.read_line(&mut line).unwrap();
                targets.push(line.split_whitespace().nth(1).unwrap().to_string());
                let mut authenticated = false;
                loop {
                    line.clear();
                    reader.read_line(&mut line).unwrap();
                    if line == "\r\n" {
                        break;
                    }
                    if line
                        .to_ascii_lowercase()
                        .starts_with("x-auth-token: test-key")
                    {
                        authenticated = true;
                    }
                }
                assert!(authenticated);
                write!(stream, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body).unwrap();
            }
            targets
        });
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();
        let snapshot = client.fetch_initial_articles().unwrap();
        let targets = worker.join().unwrap();
        assert_eq!(
            snapshot.categories,
            vec![Category {
                id: 1,
                title: "Category".into()
            }]
        );
        assert_eq!(
            snapshot.feeds,
            vec![Feed {
                id: 9,
                category_id: 1,
                title: "Feed".into()
            }]
        );
        assert_eq!(snapshot.articles.len(), 1);
        assert_eq!(
            snapshot.enclosures,
            vec![
                Enclosure {
                    id: 40,
                    article_id: 4,
                    url: "audio.mp3".into(),
                    mime_type: "audio/mpeg".into(),
                    size_bytes: None,
                    remote_media_progression_seconds: 0,
                },
                Enclosure {
                    id: 41,
                    article_id: 4,
                    url: "/cover.jpg".into(),
                    mime_type: "image/jpeg".into(),
                    size_bytes: None,
                    remote_media_progression_seconds: 0,
                },
            ]
        );
        assert_eq!(
            snapshot.articles[0].raw_html_content,
            "<p>source &amp; preview</p>"
        );
        assert_eq!(snapshot.articles[0].preview, "source & preview");
        assert_eq!(
            snapshot.articles[0].image_url.as_deref(),
            Some("https://entry/cover.jpg")
        );
        assert!(!snapshot.articles[0].is_read);
        assert!(snapshot.articles[0].is_starred);
        assert!(
            targets
                .iter()
                .any(|target| target.contains("status=unread"))
        );
        assert!(targets.iter().any(|target| target.contains("starred=1")));
        assert!(!targets.iter().any(|target| target.contains("status=read")));
    }

    #[test]
    fn maps_complete_multiple_enclosures_and_normalizes_sizes() {
        let enclosures: Vec<EnclosureDto> = serde_json::from_str(
            r#"[
                {"id":101,"entry_id":7,"url":"https://cdn.test/one.mp3","mime_type":"audio/mpeg","size":42,"media_progression":17},
                {"id":102,"entry_id":7,"url":"https://cdn.test/two.ogg","mime_type":"audio/ogg","size":0,"media_progression":0},
                {"id":103,"entry_id":7,"url":"https://cdn.test/cover","mime_type":"application/x-cover","size":-1,"media_progression":9},
                {"id":104,"entry_id":7,"url":"https://cdn.test/video.mp4","mime_type":"video/mp4"}
            ]"#,
        )
        .unwrap();

        let mapped = map_enclosures(7, enclosures).unwrap();

        assert_eq!(mapped.len(), 4);
        assert_eq!(mapped[0].id, 101);
        assert_eq!(mapped[0].article_id, 7);
        assert_eq!(mapped[1].article_id, 7);
        assert_eq!(mapped[0].size_bytes, Some(42));
        assert_eq!(mapped[0].remote_media_progression_seconds, 17);
        assert_eq!(mapped[1].size_bytes, None);
        assert_eq!(mapped[2].size_bytes, None);
        assert_eq!(mapped[2].mime_type, "application/x-cover");
        assert_eq!(mapped[3].size_bytes, None);
        assert_eq!(mapped[3].remote_media_progression_seconds, 0);
        assert!(map_enclosures(7, vec![]).unwrap().is_empty());
    }
    #[test]
    fn fetches_feed_icon_data_url() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let worker = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut request = String::new();
            reader.read_line(&mut request).unwrap();
            while !request.ends_with("\r\n\r\n") {
                let mut line = String::new();
                reader.read_line(&mut line).unwrap();
                request.push_str(&line);
                if line == "\r\n" {
                    break;
                }
            }
            assert!(request.starts_with("GET /v1/feeds/9/icon HTTP/1.1"));
            let body = r#"{"id":9,"data":"image/png;base64,AA==","mime_type":"image/png"}"#;
            write!(stream, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body).unwrap();
        });
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();
        assert_eq!(
            client.fetch_feed_icon(9).unwrap().as_deref(),
            Some("data:image/png;base64,AA==")
        );
        worker.join().unwrap();
    }
    #[test]
    fn treats_missing_feed_icon_as_unavailable() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let worker = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut request = String::new();
            reader.read_line(&mut request).unwrap();
            assert!(request.starts_with("GET /v1/feeds/9/icon HTTP/1.1"));
            write!(
                stream,
                "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            )
            .unwrap();
        });
        let client = MinifluxClient::new(&format!("http://{address}"), "test-key").unwrap();
        assert_eq!(client.fetch_feed_icon(9).unwrap(), None);
        worker.join().unwrap();
    }
}
