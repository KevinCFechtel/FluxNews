use std::collections::HashMap;
use std::fs;
use std::io::Cursor;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, Weak};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use image::{ImageFormat, imageops::FilterType};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::domain::{ArticleThumbnailResult, CoreError, CoreErrorKind};
use crate::miniflux::RemoteSource;

const PROCESSING_VERSION: u8 = 1;
const MAX_EDGE: u32 = 640;
const MAX_PAYLOAD_BYTES: usize = 20 * 1024 * 1024;
const DEFAULT_MAX_CACHE_BYTES: u64 = 1024 * 1024 * 1024;
const NEGATIVE_CACHE_AGE: Duration = Duration::from_secs(24 * 60 * 60);

#[derive(Deserialize, Serialize)]
struct Metadata {
    last_accessed_unix_millis: u64,
}

pub struct ArticleThumbnailService {
    root: PathBuf,
    max_cache_bytes: u64,
    gates: Mutex<HashMap<String, Weak<Mutex<()>>>>,
}

impl ArticleThumbnailService {
    pub fn new(cache: PathBuf) -> Result<Self, CoreError> {
        Self::with_max_cache_bytes(cache, DEFAULT_MAX_CACHE_BYTES)
    }

    fn with_max_cache_bytes(cache: PathBuf, max_cache_bytes: u64) -> Result<Self, CoreError> {
        let root = cache
            .join("article-thumbnails")
            .join(format!("v{PROCESSING_VERSION}"));
        fs::create_dir_all(&root).map_err(cache_error)?;
        Ok(Self {
            root,
            max_cache_bytes,
            gates: Mutex::new(HashMap::new()),
        })
    }

    pub fn get(
        &self,
        remote: &dyn RemoteSource,
        article_id: i64,
        image_url: &str,
    ) -> Result<ArticleThumbnailResult, CoreError> {
        if article_id <= 0 {
            return Err(CoreError::data("article ID must be positive"));
        }
        let url = url::Url::parse(image_url)
            .map_err(|_| CoreError::data("article image URL is invalid"))?;
        if !matches!(url.scheme(), "http" | "https") {
            return Err(CoreError::data("article image URL must use HTTP(S)"));
        }
        let key = resource_key(article_id, image_url);
        let gate = {
            let mut gates = self
                .gates
                .lock()
                .map_err(|_| CoreError::internal("article thumbnail gates poisoned"))?;
            match gates.entry(key.clone()) {
                std::collections::hash_map::Entry::Occupied(mut entry) => {
                    entry.get().upgrade().unwrap_or_else(|| {
                        let gate = Arc::new(Mutex::new(()));
                        entry.insert(Arc::downgrade(&gate));
                        gate
                    })
                }
                std::collections::hash_map::Entry::Vacant(entry) => {
                    let gate = Arc::new(Mutex::new(()));
                    entry.insert(Arc::downgrade(&gate));
                    gate
                }
            }
        };
        let _gate = gate
            .lock()
            .map_err(|_| CoreError::internal("article thumbnail gate poisoned"))?;
        let result = self.get_locked(remote, article_id, image_url, &key);
        drop(_gate);
        self.release_gate(&key, &gate)?;
        result
    }
    pub fn clear(&self) -> Result<(), CoreError> {
        if self.root.exists() {
            fs::remove_dir_all(&self.root).map_err(cache_error)?;
        }
        fs::create_dir_all(&self.root).map_err(cache_error)?;
        self.gates
            .lock()
            .map_err(|_| CoreError::internal("article thumbnail gates poisoned"))?
            .clear();
        Ok(())
    }

    fn get_locked(
        &self,
        remote: &dyn RemoteSource,
        article_id: i64,
        image_url: &str,
        key: &str,
    ) -> Result<ArticleThumbnailResult, CoreError> {
        let thumbnail = self.thumbnail_path(key);
        if let Some(png_data) = read_if_file(&thumbnail)? {
            self.write_metadata(key)?;
            tracing::debug!(target: "article_thumbnail", "thumbnail cache hit article_id={article_id}");
            return Ok(ArticleThumbnailResult::Available { png_data });
        }
        let unavailable = self.unavailable_path(key);
        if unavailable.exists() && is_fresh(&unavailable, NEGATIVE_CACHE_AGE) {
            tracing::debug!(target: "article_thumbnail", "thumbnail negative cache hit article_id={article_id}");
            return Ok(ArticleThumbnailResult::Unavailable);
        }
        if unavailable.exists() {
            fs::remove_file(&unavailable).map_err(cache_error)?;
        }

        tracing::debug!(target: "article_thumbnail", "thumbnail acquisition started article_id={article_id}");
        let image = match remote.fetch_article_image(image_url, MAX_PAYLOAD_BYTES) {
            Ok(image) => image,
            Err(error) if permanently_unavailable(&error) => {
                self.write_unavailable(key)?;
                tracing::debug!(target: "article_thumbnail", "thumbnail unavailable article_id={article_id}");
                return Ok(ArticleThumbnailResult::Unavailable);
            }
            Err(error) => {
                tracing::warn!(target: "article_thumbnail", "thumbnail acquisition transient failure article_id={article_id} kind={:?}", error.kind);
                return Err(error);
            }
        };
        if image.bytes.len() > MAX_PAYLOAD_BYTES {
            self.write_unavailable(key)?;
            return Ok(ArticleThumbnailResult::Unavailable);
        }
        if image
            .content_type
            .as_deref()
            .is_some_and(|content_type| !content_type.to_ascii_lowercase().starts_with("image/"))
        {
            self.write_unavailable(key)?;
            return Ok(ArticleThumbnailResult::Unavailable);
        }
        let png_data = match normalize(&image.bytes) {
            Ok(png_data) => png_data,
            Err(_) => {
                self.write_unavailable(key)?;
                return Ok(ArticleThumbnailResult::Unavailable);
            }
        };
        write_file(&thumbnail, &png_data)?;
        self.write_metadata(key)?;
        self.evict()?;
        tracing::debug!(target: "article_thumbnail", "thumbnail normalization completed article_id={article_id}");
        Ok(ArticleThumbnailResult::Available { png_data })
    }

    fn release_gate(&self, key: &str, gate: &Arc<Mutex<()>>) -> Result<(), CoreError> {
        let mut gates = self
            .gates
            .lock()
            .map_err(|_| CoreError::internal("article thumbnail gates poisoned"))?;
        if Arc::strong_count(gate) == 1
            && gates
                .get(key)
                .is_some_and(|current| current.ptr_eq(&Arc::downgrade(gate)))
        {
            gates.remove(key);
        }
        Ok(())
    }

    #[cfg(test)]
    fn gate_count(&self) -> usize {
        self.gates.lock().unwrap().len()
    }

    fn thumbnail_path(&self, key: &str) -> PathBuf {
        self.root.join(format!("{key}.png"))
    }
    fn metadata_path(&self, key: &str) -> PathBuf {
        self.root.join(format!("{key}.json"))
    }
    fn unavailable_path(&self, key: &str) -> PathBuf {
        self.root.join(format!("{key}.missing"))
    }
    fn write_metadata(&self, key: &str) -> Result<(), CoreError> {
        let metadata = Metadata {
            last_accessed_unix_millis: now_unix_millis(),
        };
        let bytes = serde_json::to_vec(&metadata)
            .map_err(|error| CoreError::internal(format!("encode thumbnail metadata: {error}")))?;
        write_file(&self.metadata_path(key), &bytes)
    }
    fn write_unavailable(&self, key: &str) -> Result<(), CoreError> {
        write_file(&self.unavailable_path(key), b"1")?;
        self.evict()
    }
    fn evict(&self) -> Result<(), CoreError> {
        let mut entries = Vec::new();
        let mut total = 0u64;
        for item in fs::read_dir(&self.root).map_err(cache_error)? {
            let item = item.map_err(cache_error)?;
            let path = item.path();
            if path
                .extension()
                .is_some_and(|extension| extension == "png" || extension == "missing")
            {
                let thumbnail_size = item.metadata().map_err(cache_error)?.len();
                let key = path
                    .file_stem()
                    .and_then(|name| name.to_str())
                    .unwrap_or_default();
                let metadata_size = fs::metadata(self.metadata_path(key))
                    .map(|metadata| metadata.len())
                    .unwrap_or(0);
                let size = thumbnail_size + metadata_size;
                total += size;
                entries.push((
                    self.last_accessed(key).max(modified_unix_millis(&path)),
                    path,
                    size,
                ));
            }
        }
        entries.sort_by_key(|(last_accessed, _, _)| *last_accessed);
        for (_, thumbnail, size) in entries {
            if total <= self.max_cache_bytes {
                break;
            }
            let key = thumbnail
                .file_stem()
                .and_then(|name| name.to_str())
                .unwrap_or_default();
            fs::remove_file(&thumbnail).map_err(cache_error)?;
            match fs::remove_file(self.metadata_path(key)) {
                Ok(()) => {}
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                Err(error) => return Err(cache_error(error)),
            }
            total -= size;
        }
        Ok(())
    }
    fn last_accessed(&self, key: &str) -> u64 {
        fs::read(self.metadata_path(key))
            .ok()
            .and_then(|data| serde_json::from_slice::<Metadata>(&data).ok())
            .map(|metadata| metadata.last_accessed_unix_millis)
            .unwrap_or(0)
    }
}

fn resource_key(article_id: i64, image_url: &str) -> String {
    let hash = Sha256::digest(image_url.as_bytes());
    let hash = hash
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    format!("{article_id}-{hash}")
}
fn normalize(bytes: &[u8]) -> Result<Vec<u8>, CoreError> {
    let image = image::load_from_memory(bytes)
        .map_err(|error| CoreError::data(format!("decode article image: {error}")))?;
    let resized = if image.width().max(image.height()) > MAX_EDGE {
        image.resize(MAX_EDGE, MAX_EDGE, FilterType::Lanczos3)
    } else {
        image
    };
    let mut png = Vec::new();
    resized
        .write_to(&mut Cursor::new(&mut png), ImageFormat::Png)
        .map_err(|error| CoreError::data(format!("encode article thumbnail: {error}")))?;
    Ok(png)
}
fn permanently_unavailable(error: &CoreError) -> bool {
    matches!(
        error.kind,
        CoreErrorKind::Data | CoreErrorKind::Authentication | CoreErrorKind::InvalidConfiguration
    )
}
fn is_fresh(path: &Path, maximum_age: Duration) -> bool {
    fs::metadata(path)
        .and_then(|metadata| metadata.modified())
        .and_then(|modified| {
            SystemTime::now()
                .duration_since(modified)
                .map_err(std::io::Error::other)
        })
        .is_ok_and(|age| age < maximum_age)
}
fn now_unix_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .try_into()
        .unwrap_or(u64::MAX)
}
fn modified_unix_millis(path: &Path) -> u64 {
    fs::metadata(path)
        .and_then(|metadata| metadata.modified())
        .and_then(|modified| {
            modified
                .duration_since(UNIX_EPOCH)
                .map_err(std::io::Error::other)
        })
        .map(|duration| duration.as_millis().try_into().unwrap_or(u64::MAX))
        .unwrap_or(0)
}
fn read_if_file(path: &Path) -> Result<Option<Vec<u8>>, CoreError> {
    match fs::read(path) {
        Ok(data) => Ok(Some(data)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(cache_error(error)),
    }
}
fn write_file(path: &Path, data: &[u8]) -> Result<(), CoreError> {
    let temporary = path.with_extension("tmp");
    fs::write(&temporary, data).map_err(cache_error)?;
    fs::rename(temporary, path).map_err(cache_error)
}
fn cache_error(error: std::io::Error) -> CoreError {
    CoreError::persistence(format!("article thumbnail cache: {error}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::miniflux::{RemoteImage, RemoteSnapshot};
    use image::{DynamicImage, GenericImageView};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::thread;
    use tempfile::TempDir;

    struct Source {
        response: Result<RemoteImage, CoreError>,
        calls: AtomicUsize,
        max_bytes: AtomicUsize,
    }
    impl RemoteSource for Source {
        fn fetch_initial_articles(&self) -> Result<RemoteSnapshot, CoreError> {
            unreachable!()
        }
        fn set_read_state(&self, _: &[i64], _: bool) -> Result<(), CoreError> {
            unreachable!()
        }
        fn set_starred_state(&self, _: i64, _: bool) -> Result<(), CoreError> {
            unreachable!()
        }
        fn fetch_article_image(&self, _: &str, max_bytes: usize) -> Result<RemoteImage, CoreError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            self.max_bytes.store(max_bytes, Ordering::SeqCst);
            match &self.response {
                Ok(image) => Ok(RemoteImage {
                    content_type: image.content_type.clone(),
                    bytes: image.bytes.clone(),
                }),
                Err(error) => Err(error.clone()),
            }
        }
    }
    fn png(width: u32, height: u32) -> Vec<u8> {
        let mut bytes = Vec::new();
        DynamicImage::ImageRgba8(image::RgbaImage::new(width, height))
            .write_to(&mut Cursor::new(&mut bytes), ImageFormat::Png)
            .unwrap();
        bytes
    }
    fn source(response: Result<RemoteImage, CoreError>) -> Source {
        Source {
            response,
            calls: AtomicUsize::new(0),
            max_bytes: AtomicUsize::new(0),
        }
    }
    #[test]
    fn normalizes_without_upscale_and_caches_by_article_and_url() {
        let temp = TempDir::new().unwrap();
        let service = ArticleThumbnailService::new(temp.path().into()).unwrap();
        let source = source(Ok(RemoteImage {
            content_type: Some("image/png".into()),
            bytes: png(1600, 400),
        }));
        let first = service.get(&source, 7, "https://image.test/a.png").unwrap();
        let second = service.get(&source, 7, "https://image.test/a.png").unwrap();
        let ArticleThumbnailResult::Available { png_data } = first else {
            panic!("expected thumbnail")
        };
        assert_eq!(
            image::load_from_memory(&png_data).unwrap().dimensions(),
            (640, 160)
        );
        assert!(matches!(second, ArticleThumbnailResult::Available { .. }));
        assert_eq!(source.calls.load(Ordering::SeqCst), 1);
        assert_eq!(source.max_bytes.load(Ordering::SeqCst), MAX_PAYLOAD_BYTES);
        assert_eq!(service.gate_count(), 0);
        let small = normalize(&png(80, 40)).unwrap();
        assert_eq!(
            image::load_from_memory(&small).unwrap().dimensions(),
            (80, 40)
        );
    }
    #[test]
    fn permanent_failures_are_negatively_cached_but_transient_failures_are_not() {
        let temp = TempDir::new().unwrap();
        let service = ArticleThumbnailService::new(temp.path().into()).unwrap();
        let permanent = source(Err(CoreError::data("not found")));
        assert!(matches!(
            service.get(&permanent, 7, "https://image.test/a"),
            Ok(ArticleThumbnailResult::Unavailable)
        ));
        assert!(matches!(
            service.get(&permanent, 7, "https://image.test/a"),
            Ok(ArticleThumbnailResult::Unavailable)
        ));
        assert_eq!(permanent.calls.load(Ordering::SeqCst), 1);
        assert_eq!(service.gate_count(), 0);
        let transient = source(Err(CoreError::connectivity("offline")));
        assert!(service.get(&transient, 8, "https://image.test/b").is_err());
        assert!(service.get(&transient, 8, "https://image.test/b").is_err());
        assert_eq!(transient.calls.load(Ordering::SeqCst), 2);
        assert_eq!(service.gate_count(), 0);
    }
    #[test]
    fn concurrent_requests_for_one_resource_fetch_once() {
        let temp = TempDir::new().unwrap();
        let service = Arc::new(ArticleThumbnailService::new(temp.path().into()).unwrap());
        let source = Arc::new(source(Ok(RemoteImage {
            content_type: Some("image/png".into()),
            bytes: png(16, 16),
        })));
        let first = {
            let service = service.clone();
            let source = source.clone();
            thread::spawn(move || service.get(source.as_ref(), 7, "https://image.test/a"))
        };
        let second = {
            let service = service.clone();
            let source = source.clone();
            thread::spawn(move || service.get(source.as_ref(), 7, "https://image.test/a"))
        };
        assert!(matches!(
            first.join().unwrap(),
            Ok(ArticleThumbnailResult::Available { .. })
        ));
        assert!(matches!(
            second.join().unwrap(),
            Ok(ArticleThumbnailResult::Available { .. })
        ));
        assert_eq!(source.calls.load(Ordering::SeqCst), 1);
        assert_eq!(service.gate_count(), 0);
    }
    #[test]
    fn size_limit_evicts_least_recently_used_thumbnails() {
        let temp = TempDir::new().unwrap();
        let encoded = png(64, 64);
        let service = ArticleThumbnailService::with_max_cache_bytes(
            temp.path().into(),
            (encoded.len() * 2) as u64,
        )
        .unwrap();
        let source = source(Ok(RemoteImage {
            content_type: Some("image/png".into()),
            bytes: encoded,
        }));
        service.get(&source, 7, "https://image.test/a").unwrap();
        thread::sleep(Duration::from_millis(2));
        service.get(&source, 8, "https://image.test/b").unwrap();
        assert_eq!(source.calls.load(Ordering::SeqCst), 2);
        service.get(&source, 7, "https://image.test/a").unwrap();
        assert_eq!(source.calls.load(Ordering::SeqCst), 3);
    }
    #[test]
    fn clear_removes_regenerable_cached_thumbnails() {
        let temp = TempDir::new().unwrap();
        let service = ArticleThumbnailService::new(temp.path().into()).unwrap();
        fs::write(service.root.join("stale.png"), b"stale").unwrap();

        service.clear().unwrap();

        assert!(service.root.is_dir());
        assert!(fs::read_dir(&service.root).unwrap().next().is_none());
    }
}
