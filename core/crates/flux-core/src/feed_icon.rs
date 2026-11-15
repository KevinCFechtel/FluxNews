use std::collections::HashMap;
use std::fs;
use std::io::Cursor;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime};

use base64::Engine;
use image::{
    DynamicImage, ImageFormat, RgbaImage,
    imageops::{FilterType, overlay},
};
use tiny_skia::{Pixmap, Transform};

use crate::domain::{CoreError, FeedIcon, FeedIconVariant};
use crate::miniflux::RemoteSource;

// Version 1 negative-cached valid Miniflux payloads before their wire shape was handled.
const PROCESSING_VERSION: u8 = 3;
const SIZE: u32 = 32;
const MAX_CACHE_AGE: Duration = Duration::from_secs(7 * 24 * 60 * 60);

pub struct FeedIconService {
    root: PathBuf,
    gates: Mutex<HashMap<i64, Arc<Mutex<()>>>>,
}

impl FeedIconService {
    pub fn new(cache: PathBuf) -> Result<Self, CoreError> {
        let root = cache
            .join("feed-icons")
            .join(format!("v{PROCESSING_VERSION}"));
        fs::create_dir_all(&root).map_err(cache_error)?;
        Ok(Self {
            root,
            gates: Mutex::new(HashMap::new()),
        })
    }

    pub fn get(
        &self,
        remote: &dyn RemoteSource,
        feed_id: i64,
        variant: FeedIconVariant,
    ) -> Result<Option<FeedIcon>, CoreError> {
        if feed_id <= 0 {
            return Err(CoreError::data("feed ID must be positive"));
        }
        let gate = self
            .gates
            .lock()
            .map_err(|_| CoreError::internal("feed icon gates poisoned"))?
            .entry(feed_id)
            .or_insert_with(|| Arc::new(Mutex::new(())))
            .clone();
        let _gate = gate
            .lock()
            .map_err(|_| CoreError::internal("feed icon gate poisoned"))?;
        let path = self.path(feed_id, variant);
        let cached = read_if_file(&path)?;
        if let Some(png) = cached.as_ref().filter(|_| is_fresh(&path)) {
            tracing::debug!(target: "feed_icon", "feed icon cache hit feed_id={feed_id}");
            return Ok(Some(FeedIcon {
                feed_id,
                variant,
                png_data: png.clone(),
            }));
        }
        let missing_path = self.missing_path(feed_id);
        if missing_path.exists() && is_fresh(&missing_path) {
            tracing::debug!(target: "feed_icon", "feed icon unavailable from cache feed_id={feed_id}");
            return Ok(None);
        }
        tracing::debug!(target: "feed_icon", "feed icon acquisition started feed_id={feed_id}");
        let data_url = match remote.fetch_feed_icon(feed_id) {
            Ok(data_url) => data_url,
            Err(error) if cached.is_some() => {
                tracing::warn!(target: "feed_icon", "feed icon refresh failed; using stale cache feed_id={feed_id} kind={:?}", error.kind);
                return Ok(cached.map(|png_data| FeedIcon {
                    feed_id,
                    variant,
                    png_data,
                }));
            }
            Err(error) => return Err(error),
        };
        let Some(data_url) = data_url else {
            self.write_missing(feed_id)?;
            tracing::debug!(target: "feed_icon", "feed icon unavailable feed_id={feed_id}");
            return Ok(None);
        };
        let Some(decoded) = decode_data_url(&data_url) else {
            self.write_missing(feed_id)?;
            tracing::warn!(target: "feed_icon", "feed icon processing failed feed_id={feed_id}");
            return Ok(None);
        };
        let (normal, dark) = match decoded {
            DecodedIcon::AdaptiveSvg { light, dark } => (normalize(&light)?, normalize(&dark)?),
            DecodedIcon::Image(image) => {
                let normal = normalize(&image)?;
                let dark = if should_lighten(&image) {
                    normalize(&lighten(&image))?
                } else {
                    normal.clone()
                };
                (normal, dark)
            }
        };
        write_file(&self.path(feed_id, FeedIconVariant::Normal), &normal)?;
        write_file(&self.path(feed_id, FeedIconVariant::Dark), &dark)?;
        tracing::debug!(target: "feed_icon", "feed icon acquisition completed feed_id={feed_id}");
        Ok(Some(FeedIcon {
            feed_id,
            variant,
            png_data: if variant == FeedIconVariant::Normal {
                normal
            } else {
                dark
            },
        }))
    }
    pub fn clear(&self) -> Result<(), CoreError> {
        if self.root.exists() {
            fs::remove_dir_all(&self.root).map_err(cache_error)?;
        }
        fs::create_dir_all(&self.root).map_err(cache_error)?;
        self.gates
            .lock()
            .map_err(|_| CoreError::internal("feed icon gates poisoned"))?
            .clear();
        Ok(())
    }

    fn path(&self, feed_id: i64, variant: FeedIconVariant) -> PathBuf {
        let name = match variant {
            FeedIconVariant::Normal => "normal",
            FeedIconVariant::Dark => "dark",
        };
        self.root.join(format!("{feed_id}-{name}.png"))
    }
    fn missing_path(&self, feed_id: i64) -> PathBuf {
        self.root.join(format!("{feed_id}.missing"))
    }
    fn write_missing(&self, feed_id: i64) -> Result<(), CoreError> {
        write_file(&self.missing_path(feed_id), b"")
    }
}
fn is_fresh(path: &Path) -> bool {
    fs::metadata(path)
        .and_then(|metadata| metadata.modified())
        .and_then(|modified| {
            SystemTime::now()
                .duration_since(modified)
                .map_err(std::io::Error::other)
        })
        .is_ok_and(|age| age < MAX_CACHE_AGE)
}

enum DecodedIcon {
    Image(RgbaImage),
    AdaptiveSvg { light: RgbaImage, dark: RgbaImage },
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum ColorScheme {
    Light,
    Dark,
}

fn decode_data_url(value: &str) -> Option<DecodedIcon> {
    let (metadata, payload) = value.trim().strip_prefix("data:")?.split_once(',')?;
    let mime = metadata.split(';').next()?.to_ascii_lowercase();
    if !mime.starts_with("image/") {
        return None;
    }
    let bytes = if metadata
        .split(';')
        .any(|part| part.eq_ignore_ascii_case("base64"))
    {
        base64::engine::general_purpose::STANDARD
            .decode(payload)
            .ok()?
    } else {
        percent_decode(payload)?
    };
    if mime == "image/svg+xml" {
        let original = render_svg(&bytes)?;
        // A dark rule is the minimum complete author-provided pair: default styling is Light.
        let adaptive = prepare_svg_for_scheme(&bytes, ColorScheme::Light)
            .ok()
            .flatten()
            .zip(
                prepare_svg_for_scheme(&bytes, ColorScheme::Dark)
                    .ok()
                    .flatten(),
            )
            .and_then(|(light, dark)| Some((render_svg(&light)?, render_svg(&dark)?)));
        Some(match adaptive {
            Some((light, dark)) => DecodedIcon::AdaptiveSvg { light, dark },
            None => DecodedIcon::Image(original),
        })
    } else {
        image::load_from_memory(&bytes)
            .ok()
            .map(|image| DecodedIcon::Image(image.to_rgba8()))
    }
}

fn render_svg(bytes: &[u8]) -> Option<RgbaImage> {
    let tree = usvg::Tree::from_data(bytes, &usvg::Options::default()).ok()?;
    let size = tree.size();
    let scale = (SIZE as f32 / size.width()).min(SIZE as f32 / size.height());
    let mut pixmap = Pixmap::new(SIZE, SIZE)?;
    let x = (SIZE as f32 - size.width() * scale) / 2.0;
    let y = (SIZE as f32 - size.height() * scale) / 2.0;
    resvg::render(
        &tree,
        Transform::from_translate(x, y).post_scale(scale, scale),
        &mut pixmap.as_mut(),
    );
    RgbaImage::from_raw(SIZE, SIZE, pixmap.take())
}

/// Resolves only standalone prefers-color-scheme media blocks inside SVG style elements.
/// `None` means no supported dark rule was found, so callers retain normal SVG handling.
fn prepare_svg_for_scheme(svg: &[u8], scheme: ColorScheme) -> Result<Option<Vec<u8>>, ()> {
    let text = std::str::from_utf8(svg).map_err(|_| ())?;
    let lower = text.to_ascii_lowercase();
    let mut output = String::with_capacity(text.len());
    let mut cursor = 0;
    let mut found_dark = false;
    while let Some(relative_start) = lower[cursor..].find("<style") {
        let start = cursor + relative_start;
        let tag_end = lower[start..].find('>').ok_or(())? + start + 1;
        let content_start = tag_end;
        let end_start = lower[content_start..].find("</style").ok_or(())? + content_start;
        let end = lower[end_start..].find('>').ok_or(())? + end_start + 1;
        output.push_str(&text[cursor..content_start]);
        let (css, prefix, suffix) = split_cdata(&text[content_start..end_start]);
        let (prepared, has_dark) = prepare_css(css, scheme)?;
        found_dark |= has_dark;
        output.push_str(prefix);
        output.push_str(&prepared);
        output.push_str(suffix);
        cursor = end_start;
        output.push_str(&text[cursor..end]);
        cursor = end;
    }
    output.push_str(&text[cursor..]);
    Ok(found_dark.then(|| output.into_bytes()))
}

fn split_cdata(css: &str) -> (&str, &str, &str) {
    let trimmed = css.trim();
    if let Some(body) = trimmed
        .strip_prefix("<![CDATA[")
        .and_then(|body| body.strip_suffix("]]>"))
    {
        (body, "<![CDATA[", "]]>")
    } else {
        (css, "", "")
    }
}

fn prepare_css(css: &str, scheme: ColorScheme) -> Result<(String, bool), ()> {
    let bytes = css.as_bytes();
    let mut output = String::with_capacity(css.len());
    let mut cursor = 0;
    let mut found_dark = false;
    while let Some(at) = find_media(bytes, cursor) {
        output.push_str(&css[cursor..at]);
        let condition_start = at + 6;
        let open = scan_to_block(bytes, condition_start).ok_or(())?;
        let close = matching_brace(bytes, open).ok_or(())?;
        let appearance = color_scheme_condition(&css[condition_start..open]);
        if let Some(appearance) = appearance {
            found_dark |= appearance == ColorScheme::Dark;
            if appearance == scheme {
                let (inner, nested_dark) = prepare_css(&css[open + 1..close], scheme)?;
                found_dark |= nested_dark;
                output.push_str(&inner);
            }
        } else {
            output.push_str(&css[at..=close]);
        }
        cursor = close + 1;
    }
    output.push_str(&css[cursor..]);
    Ok((output, found_dark))
}

fn find_media(bytes: &[u8], start: usize) -> Option<usize> {
    let mut index = start;
    let mut quote = None;
    while index < bytes.len() {
        if let Some(next) = skip_css_ignored(bytes, index, &mut quote) {
            index = next;
            continue;
        }
        if index + 6 <= bytes.len()
            && bytes[index] == b'@'
            && bytes[index + 1..index + 6].eq_ignore_ascii_case(b"media")
            && !bytes.get(index + 6).is_some_and(u8::is_ascii_alphabetic)
        {
            return Some(index);
        }
        index += 1;
    }
    None
}

fn skip_css_ignored(bytes: &[u8], index: usize, quote: &mut Option<u8>) -> Option<usize> {
    if let Some(active_quote) = quote {
        if bytes[index] == b'\\' {
            return Some((index + 2).min(bytes.len()));
        }
        if bytes[index] == *active_quote {
            *quote = None;
        }
        return Some(index + 1);
    }
    if bytes[index] == b'\'' || bytes[index] == b'"' {
        *quote = Some(bytes[index]);
        return Some(index + 1);
    }
    if bytes[index..].starts_with(b"/*") {
        return bytes[index + 2..]
            .windows(2)
            .position(|window| window == b"*/")
            .map(|offset| index + offset + 4);
    }
    None
}

fn scan_to_block(bytes: &[u8], mut index: usize) -> Option<usize> {
    let mut quote = None;
    while index < bytes.len() {
        if let Some(next) = skip_css_ignored(bytes, index, &mut quote) {
            index = next;
            continue;
        }
        match bytes[index] {
            b'{' => return Some(index),
            b';' => return None,
            _ => index += 1,
        }
    }
    None
}

fn matching_brace(bytes: &[u8], open: usize) -> Option<usize> {
    let mut depth = 0_u32;
    let mut quote = None;
    let mut index = open;
    while index < bytes.len() {
        if let Some(next) = skip_css_ignored(bytes, index, &mut quote) {
            index = next;
            continue;
        }
        match bytes[index] {
            b'{' => depth += 1,
            b'}' => {
                depth = depth.checked_sub(1)?;
                if depth == 0 {
                    return Some(index);
                }
            }
            _ => {}
        }
        index += 1;
    }
    None
}

fn color_scheme_condition(condition: &str) -> Option<ColorScheme> {
    let compact = condition
        .bytes()
        .filter(|byte| !byte.is_ascii_whitespace())
        .map(char::from)
        .collect::<String>()
        .to_ascii_lowercase();
    match compact.as_str() {
        "(prefers-color-scheme:light)" => Some(ColorScheme::Light),
        "(prefers-color-scheme:dark)" => Some(ColorScheme::Dark),
        _ => None,
    }
}

fn percent_decode(input: &str) -> Option<Vec<u8>> {
    let mut output = Vec::with_capacity(input.len());
    let bytes = input.as_bytes();
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' {
            output.push(hex(*bytes.get(index + 1)?)? << 4 | hex(*bytes.get(index + 2)?)?);
            index += 3;
        } else {
            output.push(bytes[index]);
            index += 1;
        }
    }
    Some(output)
}
fn hex(value: u8) -> Option<u8> {
    match value {
        b'0'..=b'9' => Some(value - b'0'),
        b'a'..=b'f' => Some(value - b'a' + 10),
        b'A'..=b'F' => Some(value - b'A' + 10),
        _ => None,
    }
}

fn normalize(image: &RgbaImage) -> Result<Vec<u8>, CoreError> {
    let resized = DynamicImage::ImageRgba8(image.clone())
        .resize(SIZE, SIZE, FilterType::Lanczos3)
        .to_rgba8();
    let mut canvas = RgbaImage::new(SIZE, SIZE);
    overlay(
        &mut canvas,
        &resized,
        i64::from((SIZE - resized.width()) / 2),
        i64::from((SIZE - resized.height()) / 2),
    );
    let mut png = Vec::new();
    DynamicImage::ImageRgba8(canvas)
        .write_to(&mut Cursor::new(&mut png), ImageFormat::Png)
        .map_err(|e| CoreError::data(format!("encode feed icon: {e}")))?;
    Ok(png)
}
fn should_lighten(image: &RgbaImage) -> bool {
    let visible = image
        .pixels()
        .filter(|pixel| pixel[3] > 0)
        .collect::<Vec<_>>();
    let transparent = visible.len() * 10 < (image.width() * image.height()) as usize * 9;
    let luminance = visible
        .iter()
        .map(|p| (0.2126 * p[0] as f32 + 0.7152 * p[1] as f32 + 0.0722 * p[2] as f32) / 255.0)
        .sum::<f32>()
        / visible.len().max(1) as f32;
    transparent && luminance < 0.45
}
fn lighten(image: &RgbaImage) -> RgbaImage {
    let mut background = RgbaImage::from_pixel(
        image.width(),
        image.height(),
        image::Rgba([245, 245, 245, 255]),
    );
    let radius = (image.width().min(image.height()) / 8).max(1) as i32;
    for y in 0..background.height() as i32 {
        for x in 0..background.width() as i32 {
            let dx = if x < radius {
                radius - x
            } else if x >= background.width() as i32 - radius {
                x - (background.width() as i32 - radius - 1)
            } else {
                0
            };
            let dy = if y < radius {
                radius - y
            } else if y >= background.height() as i32 - radius {
                y - (background.height() as i32 - radius - 1)
            } else {
                0
            };
            if dx * dx + dy * dy > radius * radius {
                background.get_pixel_mut(x as u32, y as u32)[3] = 0;
            }
        }
    }
    overlay(&mut background, image, 0, 0);
    background
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
    CoreError::persistence(format!("feed icon cache: {error}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::GenericImageView;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::thread;
    use tempfile::TempDir;

    struct Source {
        icon: Option<String>,
        calls: AtomicUsize,
    }
    impl RemoteSource for Source {
        fn fetch_initial_articles(&self) -> Result<crate::miniflux::RemoteSnapshot, CoreError> {
            unreachable!()
        }
        fn set_read_state(&self, _: &[i64], _: bool) -> Result<(), CoreError> {
            unreachable!()
        }
        fn set_starred_state(&self, _: i64, _: bool) -> Result<(), CoreError> {
            unreachable!()
        }
        fn fetch_feed_icon(&self, _: i64) -> Result<Option<String>, CoreError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            Ok(self.icon.clone())
        }
    }

    fn svg_data_url(svg: &str) -> String {
        format!(
            "data:image/svg+xml;base64,{}",
            base64::engine::general_purpose::STANDARD.encode(svg)
        )
    }

    fn pixel(png: &[u8], x: u32, y: u32) -> image::Rgba<u8> {
        image::load_from_memory(png)
            .unwrap()
            .to_rgba8()
            .get_pixel(x, y)
            .to_owned()
    }

    #[test]
    fn normalizes_caches_and_creates_a_light_dark_variant() {
        let temp = TempDir::new().unwrap();
        let service = FeedIconService::new(temp.path().into()).unwrap();
        let source = Source { icon: Some("data:image/svg+xml,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%2210%22%20height%3D%2210%22%3E%3Ccircle%20cx%3D%225%22%20cy%3D%225%22%20r%3D%225%22%2F%3E%3C%2Fsvg%3E".into()), calls: AtomicUsize::new(0) };
        let normal = service
            .get(&source, 4, FeedIconVariant::Normal)
            .unwrap()
            .unwrap();
        let dark = service
            .get(&source, 4, FeedIconVariant::Dark)
            .unwrap()
            .unwrap();
        assert_eq!(
            image::load_from_memory(&normal.png_data)
                .unwrap()
                .dimensions(),
            (32, 32)
        );
        assert_ne!(normal.png_data, dark.png_data);
        assert_eq!(pixel(&normal.png_data, 3, 3)[3], 0);
        assert!(pixel(&dark.png_data, 3, 3)[0] > 240);
        assert_eq!(source.calls.load(Ordering::SeqCst), 1);
    }
    #[test]
    fn dark_only_adaptive_svg_uses_author_dark_appearance_without_background() {
        let temp = TempDir::new().unwrap();
        let service = FeedIconService::new(temp.path().into()).unwrap();
        let source = Source {
            icon: Some(svg_data_url(
                r#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><style>.icon { fill: black; } @media ( prefers-color-scheme : DARK ) { .icon { fill: white; } }</style><circle class="icon" cx="5" cy="5" r="5"/></svg>"#,
            )),
            calls: AtomicUsize::new(0),
        };
        let normal = service
            .get(&source, 4, FeedIconVariant::Normal)
            .unwrap()
            .unwrap();
        let dark = service
            .get(&source, 4, FeedIconVariant::Dark)
            .unwrap()
            .unwrap();
        assert_ne!(normal.png_data, dark.png_data);
        assert!(pixel(&normal.png_data, 16, 16)[0] < 10);
        assert!(pixel(&dark.png_data, 16, 16)[0] > 245);
        assert_eq!(pixel(&dark.png_data, 0, 0)[3], 0);
    }
    #[test]
    fn explicit_light_and_dark_svg_rules_render_their_author_colors() {
        let temp = TempDir::new().unwrap();
        let service = FeedIconService::new(temp.path().into()).unwrap();
        let source = Source {
            icon: Some(svg_data_url(
                r#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><style>.icon { fill: black; } @media (prefers-color-scheme: light) { .icon { fill: red; } } @media (prefers-color-scheme: dark) { .icon { fill: blue; } }</style><rect class="icon" width="10" height="10"/></svg>"#,
            )),
            calls: AtomicUsize::new(0),
        };
        let normal = service
            .get(&source, 4, FeedIconVariant::Normal)
            .unwrap()
            .unwrap();
        let dark = service
            .get(&source, 4, FeedIconVariant::Dark)
            .unwrap()
            .unwrap();
        let light_pixel = pixel(&normal.png_data, 16, 16);
        let dark_pixel = pixel(&dark.png_data, 16, 16);
        assert!(light_pixel[0] > 245 && light_pixel[2] < 10);
        assert!(dark_pixel[2] > 245 && dark_pixel[0] < 10);
    }
    #[test]
    fn light_only_adaptive_svg_uses_existing_dark_fallback() {
        let temp = TempDir::new().unwrap();
        let service = FeedIconService::new(temp.path().into()).unwrap();
        let source = Source {
            icon: Some(svg_data_url(
                r#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><style>@media (prefers-color-scheme: light) { .icon { fill: red; } }</style><circle class="icon" cx="5" cy="5" r="5" fill="black"/></svg>"#,
            )),
            calls: AtomicUsize::new(0),
        };
        let normal = service
            .get(&source, 4, FeedIconVariant::Normal)
            .unwrap()
            .unwrap();
        let dark = service
            .get(&source, 4, FeedIconVariant::Dark)
            .unwrap()
            .unwrap();
        assert_ne!(normal.png_data, dark.png_data);
        assert_eq!(pixel(&dark.png_data, 0, 0)[3], 0);
        assert!(pixel(&dark.png_data, 16, 16)[0] < 10);
    }
    #[test]
    fn malformed_adaptive_css_falls_back_to_original_svg_rendering() {
        let svg = br#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><style>@media (prefers-color-scheme: dark) { .icon { fill: white; }</style><circle class="icon" cx="5" cy="5" r="5" fill="black"/></svg>"#;
        assert!(prepare_svg_for_scheme(svg, ColorScheme::Dark).is_err());
        assert!(matches!(
            decode_data_url(&svg_data_url(std::str::from_utf8(svg).unwrap())),
            Some(DecodedIcon::Image(_))
        ));
    }
    #[test]
    fn raster_icons_keep_existing_dark_fallback() {
        let mut png = Vec::new();
        DynamicImage::ImageRgba8(RgbaImage::from_pixel(10, 10, image::Rgba([0, 0, 0, 255])))
            .write_to(&mut Cursor::new(&mut png), ImageFormat::Png)
            .unwrap();
        let source = Source {
            icon: Some(format!(
                "data:image/png;base64,{}",
                base64::engine::general_purpose::STANDARD.encode(png)
            )),
            calls: AtomicUsize::new(0),
        };
        let temp = TempDir::new().unwrap();
        let service = FeedIconService::new(temp.path().into()).unwrap();
        let normal = service
            .get(&source, 4, FeedIconVariant::Normal)
            .unwrap()
            .unwrap();
        let dark = service
            .get(&source, 4, FeedIconVariant::Dark)
            .unwrap()
            .unwrap();
        assert_eq!(normal.png_data, dark.png_data);
    }
    #[test]
    fn caches_both_adaptive_variants_under_processing_version_three() {
        let temp = TempDir::new().unwrap();
        let service = FeedIconService::new(temp.path().into()).unwrap();
        let source = Source {
            icon: Some(svg_data_url(
                r#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><style>@media (prefers-color-scheme: dark) { .icon { fill: white; } }</style><circle class="icon" cx="5" cy="5" r="5" fill="black"/></svg>"#,
            )),
            calls: AtomicUsize::new(0),
        };
        service.get(&source, 4, FeedIconVariant::Normal).unwrap();
        service.get(&source, 4, FeedIconVariant::Dark).unwrap();
        assert_eq!(source.calls.load(Ordering::SeqCst), 1);
        assert!(temp.path().join("feed-icons/v3/4-normal.png").is_file());
        assert!(temp.path().join("feed-icons/v3/4-dark.png").is_file());
    }
    #[test]
    fn clear_removes_regenerable_cached_icons() {
        let temp = TempDir::new().unwrap();
        let service = FeedIconService::new(temp.path().into()).unwrap();
        fs::write(service.root.join("stale.png"), b"stale").unwrap();

        service.clear().unwrap();

        assert!(service.root.is_dir());
        assert!(fs::read_dir(&service.root).unwrap().next().is_none());
    }
    #[test]
    fn normalization_preserves_aspect_ratio_on_transparent_canvas() {
        let image = RgbaImage::from_pixel(80, 20, image::Rgba([255, 0, 0, 255]));
        let png = normalize(&image).unwrap();
        let normalized = image::load_from_memory(&png).unwrap().to_rgba8();
        assert_eq!(normalized.dimensions(), (32, 32));
        assert_eq!(normalized.get_pixel(16, 0)[3], 0);
        assert_eq!(normalized.get_pixel(16, 12)[3], 255);
    }
    #[test]
    fn invalid_data_is_negatively_cached() {
        let temp = TempDir::new().unwrap();
        let service = FeedIconService::new(temp.path().into()).unwrap();
        let source = Source {
            icon: Some("data:text/plain;base64,Zm9v".into()),
            calls: AtomicUsize::new(0),
        };
        assert!(
            service
                .get(&source, 4, FeedIconVariant::Normal)
                .unwrap()
                .is_none()
        );
        assert!(
            service
                .get(&source, 4, FeedIconVariant::Dark)
                .unwrap()
                .is_none()
        );
        assert_eq!(source.calls.load(Ordering::SeqCst), 1);
    }
    #[test]
    fn concurrent_requests_share_one_remote_fetch() {
        let temp = TempDir::new().unwrap();
        let service = Arc::new(FeedIconService::new(temp.path().into()).unwrap());
        let source = Arc::new(Source {
            icon: Some("data:image/svg+xml,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%2210%22%20height%3D%2210%22%3E%3Ccircle%20cx%3D%225%22%20cy%3D%225%22%20r%3D%225%22%2F%3E%3C%2Fsvg%3E".into()),
            calls: AtomicUsize::new(0),
        });
        let first = {
            let service = service.clone();
            let source = source.clone();
            thread::spawn(move || service.get(source.as_ref(), 4, FeedIconVariant::Normal))
        };
        let second = {
            let service = service.clone();
            let source = source.clone();
            thread::spawn(move || service.get(source.as_ref(), 4, FeedIconVariant::Dark))
        };
        assert!(first.join().unwrap().unwrap().is_some());
        assert!(second.join().unwrap().unwrap().is_some());
        assert_eq!(source.calls.load(Ordering::SeqCst), 1);
    }
}
