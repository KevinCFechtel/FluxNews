use std::io::Read;
use std::path::{Component, Path, PathBuf};

use html5ever::{parse_document, tendril::TendrilSink};
use symphonia::core::common::Limit;
use symphonia::core::formats::{FormatOptions, TrackType, probe::Hint};
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::{
    Chapter, ChapterGroup, ChapterGroupItem, MetadataOptions, StandardTag, StandardVisualKey,
};
use symphonia::core::units::Time;

use crate::domain::{MediaChapter, MediaChapterSource};
use crate::html_dom::{Dom, Handle, NodeData};

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct AnalyzedMedia {
    pub duration_ms: Option<u64>,
    pub artwork: Option<Vec<u8>>,
    pub embedded_chapters: Vec<MediaChapterInput>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct MediaChapterInput {
    pub title: String,
    pub start_ms: u64,
    pub end_ms: Option<u64>,
}

pub(crate) const REMOTE_MEDIA_INITIAL_PROBE_BYTES: usize = 256 * 1024;
pub(crate) const REMOTE_MEDIA_MP4_PREFIX_BYTES: usize = 1024 * 1024;
pub(crate) const REMOTE_MEDIA_MP4_TAIL_BYTES: usize = 1024 * 1024;
pub(crate) const REMOTE_MEDIA_MAX_ID3_BYTES: usize = 8 * 1024 * 1024;

pub(crate) fn id3_probe_total_bytes(prefix: &[u8]) -> Option<usize> {
    if prefix.len() < 10 || &prefix[0..3] != b"ID3" || !(prefix[3] == 3 || prefix[3] == 4) {
        return None;
    }
    let payload = syncsafe(&prefix[6..10])?;
    10usize
        .checked_add(payload)
        .filter(|total| *total <= REMOTE_MEDIA_MAX_ID3_BYTES)
}

pub(crate) fn probe_id3_artwork(bytes: &[u8]) -> Option<Vec<u8>> {
    parse_id3_artwork(bytes)
}

pub(crate) fn probe_mp4_artwork(bytes: &[u8]) -> Option<Vec<u8>> {
    let mut offset = 4usize;
    while offset.saturating_add(4) <= bytes.len() {
        if bytes.get(offset..offset + 4) == Some(&b"covr"[..]) {
            let atom_start = offset - 4;
            let size = u32::from_be_bytes(bytes.get(atom_start..offset)?.try_into().ok()?) as usize;
            let atom_end = atom_start.checked_add(size)?;
            if size >= 16 && atom_end <= bytes.len() {
                let mut child = offset + 4;
                while child.saturating_add(16) <= atom_end {
                    let child_size =
                        u32::from_be_bytes(bytes.get(child..child + 4)?.try_into().ok()?) as usize;
                    if child_size < 16 {
                        break;
                    }
                    let child_end = child.checked_add(child_size)?;
                    if child_end > atom_end {
                        break;
                    }
                    if bytes.get(child + 4..child + 8) == Some(&b"data"[..]) {
                        let payload = bytes.get(child + 16..child_end)?;
                        if is_supported_artwork(payload) {
                            return Some(payload.to_vec());
                        }
                    }
                    child = child_end;
                }
            }
        }
        offset += 1;
    }
    None
}

fn is_supported_artwork(bytes: &[u8]) -> bool {
    bytes.starts_with(&[0xFF, 0xD8, 0xFF])
        || bytes.starts_with(b"\x89PNG\r\n\x1a\n")
        || bytes.starts_with(b"RIFF") && bytes.get(8..12) == Some(&b"WEBP"[..])
}

pub(crate) fn resolve_media_reference(root: &Path, reference: &str) -> Option<PathBuf> {
    let path = Path::new(reference);
    if path.is_absolute()
        || path.components().any(|component| {
            matches!(
                component,
                Component::ParentDir | Component::RootDir | Component::Prefix(_)
            )
        })
    {
        return None;
    }
    Some(root.join(path))
}

pub(crate) fn analyze_file(path: &Path) -> AnalyzedMedia {
    if !path.is_file() {
        return AnalyzedMedia::default();
    }
    let bytes = bounded_file_prefix(path);
    let structured_chapters = bytes.as_deref().map(parse_id3_chapters).unwrap_or_default();
    // Probe bytes rather than the filename so legacy Flutter downloads with a
    // `.audio` suffix retain format-independent duration and metadata support.
    let probed = probe_media(path).unwrap_or_default();
    let duration_ms = probed.duration_ms;
    // Truncated old MP3s can still contain a valid APIC frame even when no
    // complete media stream can be probed. Keep the bounded parser as fallback.
    let artwork = probed
        .artwork
        .or_else(|| bytes.as_deref().and_then(parse_id3_artwork))
        .or_else(|| bytes.as_deref().and_then(probe_mp4_artwork));
    let mut embedded_chapters = if structured_chapters.is_empty() {
        probed.embedded_chapters
    } else {
        structured_chapters
    };
    embedded_chapters = finalize_chapters(embedded_chapters, duration_ms);
    AnalyzedMedia {
        duration_ms,
        artwork,
        embedded_chapters,
    }
}

fn probe_media(path: &Path) -> Option<AnalyzedMedia> {
    const MAX_ARTWORK_BYTES: usize = 10 * 1024 * 1024;

    let source = std::fs::File::open(path).ok()?;
    let stream = MediaSourceStream::new(Box::new(source), Default::default());
    let metadata_options = MetadataOptions::default()
        .limit_tag_bytes(Limit::Maximum(1024 * 1024))
        .limit_visual_bytes(Limit::Maximum(MAX_ARTWORK_BYTES));
    // An empty hint is intentional: callers may supply a legacy `.audio`
    // suffix, so the file signature must remain authoritative.
    let mut format = symphonia::default::get_probe()
        .probe(
            &Hint::new(),
            stream,
            FormatOptions::default(),
            metadata_options,
        )
        .ok()?;

    let duration_ms = duration_ms(format.as_ref());
    let chapters = format.chapters().map(format_chapters).unwrap_or_default();

    let mut front_cover = None;
    let mut first_visual = None;
    let mut metadata = format.metadata();
    loop {
        if let Some(revision) = metadata.current() {
            for visual in revision.media.visuals.iter().chain(
                revision
                    .per_track
                    .iter()
                    .flat_map(|track| &track.metadata.visuals),
            ) {
                if visual.data.is_empty() || visual.data.len() > MAX_ARTWORK_BYTES {
                    continue;
                }
                let data = visual.data.to_vec();
                if visual.usage == Some(StandardVisualKey::FrontCover) {
                    front_cover.get_or_insert(data);
                } else {
                    first_visual.get_or_insert(data);
                }
            }
        }
        if metadata.pop().is_none() {
            break;
        }
    }

    Some(AnalyzedMedia {
        duration_ms,
        artwork: front_cover.or(first_visual),
        embedded_chapters: chapters,
    })
}

fn duration_ms(format: &dyn symphonia::core::formats::FormatReader) -> Option<u64> {
    let media = format.media_info();
    let time = media
        .time_base
        .zip(media.duration)
        .and_then(|(time_base, duration)| time_base.calc_duration(duration))
        .or_else(|| {
            let track = format.default_track(TrackType::Audio)?;
            track
                .time_base
                .zip(track.duration)
                .and_then(|(time_base, duration)| time_base.calc_duration(duration))
        })?;
    positive_millis(time)
}

fn positive_millis(time: Time) -> Option<u64> {
    let millis = time.as_millis();
    (millis > 0).then(|| u64::try_from(millis).ok()).flatten()
}

fn format_chapters(group: &ChapterGroup) -> Vec<MediaChapterInput> {
    let mut chapters = Vec::new();
    collect_format_chapters(group, &mut chapters);
    chapters
}

fn collect_format_chapters(group: &ChapterGroup, output: &mut Vec<MediaChapterInput>) {
    for item in &group.items {
        match item {
            ChapterGroupItem::Group(group) => collect_format_chapters(group, output),
            ChapterGroupItem::Chapter(chapter) => {
                if let Some(chapter) = format_chapter(chapter) {
                    output.push(chapter);
                }
            }
        }
    }
}

fn format_chapter(chapter: &Chapter) -> Option<MediaChapterInput> {
    let title = chapter.tags.iter().find_map(|tag| match &tag.std {
        Some(StandardTag::ChapterTitle(title)) | Some(StandardTag::TrackTitle(title)) => {
            Some(title.trim().to_string())
        }
        _ => None,
    })?;
    if title.is_empty() {
        return None;
    }
    Some(MediaChapterInput {
        title,
        start_ms: positive_or_zero_millis(chapter.start_time)?,
        end_ms: chapter.end_time.and_then(positive_or_zero_millis),
    })
}

fn positive_or_zero_millis(time: Time) -> Option<u64> {
    let millis = time.as_millis();
    (millis >= 0).then(|| u64::try_from(millis).ok()).flatten()
}

fn bounded_file_prefix(path: &Path) -> Option<Vec<u8>> {
    const MAX_ID3_BYTES: u64 = 8 * 1024 * 1024;
    let file = std::fs::File::open(path).ok()?;
    let mut bytes = Vec::new();
    file.take(MAX_ID3_BYTES).read_to_end(&mut bytes).ok()?;
    Some(bytes)
}

fn parse_id3_artwork(bytes: &[u8]) -> Option<Vec<u8>> {
    if bytes.len() < 10 || &bytes[0..3] != b"ID3" || !(bytes[3] == 3 || bytes[3] == 4) {
        return None;
    }
    let tag_size = syncsafe(&bytes[6..10]).unwrap_or(0);
    let end = 10usize.saturating_add(tag_size).min(bytes.len());
    let mut offset = 10usize;
    let mut first_picture = None;

    while offset.saturating_add(10) <= end {
        let header = &bytes[offset..offset + 10];
        if header.iter().all(|byte| *byte == 0) {
            break;
        }
        let frame_size = if bytes[3] == 4 {
            syncsafe(&header[4..8])
        } else {
            Some(u32::from_be_bytes([header[4], header[5], header[6], header[7]]) as usize)
        }?;
        let frame_end = offset
            .checked_add(10)
            .and_then(|value| value.checked_add(frame_size))?;
        if frame_end > end {
            break;
        }
        if &header[0..4] == b"APIC"
            && let Some((picture_type, data)) = parse_apic(&bytes[offset + 10..frame_end])
        {
            if picture_type == 3 {
                return Some(data);
            }
            if first_picture.is_none() {
                first_picture = Some(data);
            }
        }
        offset = frame_end;
    }
    first_picture
}

fn parse_apic(payload: &[u8]) -> Option<(u8, Vec<u8>)> {
    let (&encoding, rest) = payload.split_first()?;
    let mime_end = rest.iter().position(|byte| *byte == 0)?;
    let after_mime = rest.get(mime_end + 1..)?;
    let (&picture_type, description_and_data) = after_mime.split_first()?;
    let data_start = match encoding {
        0 | 3 => description_and_data
            .iter()
            .position(|byte| *byte == 0)
            .map(|index| index + 1)?,
        1 | 2 => description_and_data
            .windows(2)
            .position(|pair| pair == [0, 0])
            .map(|index| index + 2)?,
        _ => return None,
    };
    let data = description_and_data.get(data_start..)?;
    if data.is_empty() || data.len() > REMOTE_MEDIA_MAX_ID3_BYTES || !is_supported_artwork(data) {
        return None;
    }
    Some((picture_type, data.to_vec()))
}

fn parse_id3_chapters(bytes: &[u8]) -> Vec<MediaChapterInput> {
    if bytes.len() < 10 || &bytes[0..3] != b"ID3" || !(bytes[3] == 3 || bytes[3] == 4) {
        return Vec::new();
    }
    let tag_size = syncsafe(&bytes[6..10]).unwrap_or(0);
    let end = 10usize.saturating_add(tag_size).min(bytes.len());
    let mut offset = 10usize;
    let mut chapters = Vec::new();
    while offset.saturating_add(10) <= end {
        let header = &bytes[offset..offset + 10];
        if header.iter().all(|byte| *byte == 0) {
            let Some(next) = resynchronize_frame(bytes, offset + 1, end, bytes[3]) else {
                break;
            };
            offset = next;
            continue;
        }
        let frame_size = if bytes[3] == 4 {
            syncsafe(&header[4..8])
        } else {
            Some(u32::from_be_bytes([header[4], header[5], header[6], header[7]]) as usize)
        };
        let Some(frame_size) = frame_size else {
            let Some(next) = resynchronize_frame(bytes, offset + 1, end, bytes[3]) else {
                break;
            };
            offset = next;
            continue;
        };
        let frame_end = offset
            .checked_add(10)
            .and_then(|value| value.checked_add(frame_size));
        let Some(frame_end) = frame_end.filter(|value| *value <= end) else {
            let Some(next) = resynchronize_frame(bytes, offset + 1, end, bytes[3]) else {
                break;
            };
            offset = next;
            continue;
        };
        if &header[0..4] == b"CHAP"
            && let Some(chapter) = parse_chap(&bytes[offset + 10..frame_end], bytes[3])
        {
            chapters.push(chapter);
        }
        offset = frame_end;
    }
    finalize_chapters(chapters, None)
}

fn parse_chap(payload: &[u8], version: u8) -> Option<MediaChapterInput> {
    let id_end = payload.iter().position(|byte| *byte == 0)?;
    let timing = payload.get(id_end + 1..id_end + 17)?;
    let start_ms = u64::from(u32::from_be_bytes(timing[0..4].try_into().ok()?));
    let end_raw = u32::from_be_bytes(timing[4..8].try_into().ok()?);
    let end_ms = (end_raw != u32::MAX).then_some(u64::from(end_raw));
    let title = parse_id3_title_frames(&payload[id_end + 17..], version)
        .or_else(|| String::from_utf8(payload[..id_end].to_vec()).ok())?;
    Some(MediaChapterInput {
        title,
        start_ms,
        end_ms,
    })
}

fn resynchronize_frame(bytes: &[u8], start: usize, end: usize, version: u8) -> Option<usize> {
    let last = end.checked_sub(10)?;
    for offset in start..=last {
        let header = bytes.get(offset..offset + 10)?;
        if !header[0].is_ascii_uppercase()
            || !header[1..4]
                .iter()
                .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit())
        {
            continue;
        }
        let size = if version == 4 {
            syncsafe(&header[4..8])
        } else {
            Some(u32::from_be_bytes(header[4..8].try_into().ok()?) as usize)
        }?;
        if offset
            .checked_add(10)
            .and_then(|value| value.checked_add(size))
            .is_some_and(|frame_end| frame_end <= end)
        {
            return Some(offset);
        }
    }
    None
}

fn parse_id3_title_frames(mut bytes: &[u8], version: u8) -> Option<String> {
    while bytes.len() >= 10 {
        let size = if version == 4 {
            syncsafe(&bytes[4..8])?
        } else {
            u32::from_be_bytes(bytes[4..8].try_into().ok()?) as usize
        };
        let end = 10usize.checked_add(size)?;
        if end > bytes.len() {
            return None;
        }
        if &bytes[0..4] == b"TIT2" && size > 1 {
            return decode_id3_text(&bytes[10..end]);
        }
        bytes = &bytes[end..];
    }
    None
}

fn decode_id3_text(bytes: &[u8]) -> Option<String> {
    let (encoding, value) = bytes.split_first()?;
    let text = match encoding {
        0 => value.iter().map(|byte| char::from(*byte)).collect(),
        1 | 2 => String::from_utf16(
            &value
                .chunks(2)
                .filter(|pair| pair.len() == 2)
                .map(|pair| {
                    if *encoding == 1 {
                        u16::from_le_bytes([pair[0], pair[1]])
                    } else {
                        u16::from_be_bytes([pair[0], pair[1]])
                    }
                })
                .collect::<Vec<_>>(),
        )
        .ok()?,
        3 => String::from_utf8(value.to_vec()).ok()?,
        _ => return None,
    };
    (!text.trim().is_empty())
        .then(|| text.trim_matches('\0').trim().to_string())
        .filter(|text| !text.is_empty())
}

fn syncsafe(bytes: &[u8]) -> Option<usize> {
    (bytes.len() == 4 && bytes.iter().all(|byte| byte & 0x80 == 0)).then(|| {
        usize::from(bytes[0]) << 21
            | usize::from(bytes[1]) << 14
            | usize::from(bytes[2]) << 7
            | usize::from(bytes[3])
    })
}

fn finalize_chapters(
    mut chapters: Vec<MediaChapterInput>,
    duration_ms: Option<u64>,
) -> Vec<MediaChapterInput> {
    chapters.sort_by_key(|chapter| chapter.start_ms);
    chapters.dedup_by_key(|chapter| chapter.start_ms);
    chapters.retain(|chapter| {
        !chapter.title.is_empty() && duration_ms.is_none_or(|duration| chapter.start_ms <= duration)
    });
    for chapter in &mut chapters {
        if chapter.end_ms.is_some_and(|end| {
            end <= chapter.start_ms || duration_ms.is_some_and(|duration| end > duration)
        }) {
            chapter.end_ms = None;
        }
    }
    for index in 0..chapters.len().saturating_sub(1) {
        if chapters[index].end_ms.is_none() {
            chapters[index].end_ms = Some(chapters[index + 1].start_ms);
        }
    }
    if let (Some(duration), Some(last)) = (duration_ms, chapters.last_mut())
        && duration > last.start_ms
        && last.end_ms.is_none()
    {
        last.end_ms = Some(duration);
    }
    chapters.retain(|chapter| chapter.end_ms.is_none_or(|end| end > chapter.start_ms));
    chapters
}

pub(crate) fn article_chapters(
    article_html: &str,
    duration_ms: Option<u64>,
) -> Vec<MediaChapterInput> {
    let text = article_chapter_text(article_html);
    let mut chapters = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        let Some((timestamp, title)) = line.split_once(char::is_whitespace) else {
            continue;
        };
        let Some(start_ms) = parse_timestamp(timestamp) else {
            continue;
        };
        let title = title.trim();
        if title.is_empty() || duration_ms.is_some_and(|duration| start_ms > duration) {
            continue;
        }
        chapters.push(MediaChapterInput {
            title: title.to_string(),
            start_ms,
            end_ms: None,
        });
    }
    finalize_chapters(chapters, duration_ms)
}

pub(crate) fn to_domain_chapters(
    enclosure_id: i64,
    source: MediaChapterSource,
    inputs: &[MediaChapterInput],
) -> Vec<MediaChapter> {
    inputs
        .iter()
        .map(|chapter| MediaChapter {
            enclosure_id,
            title: chapter.title.clone(),
            start_ms: chapter.start_ms,
            end_ms: chapter.end_ms,
            source,
        })
        .collect()
}

fn parse_timestamp(value: &str) -> Option<u64> {
    let parts = value.split(':').collect::<Vec<_>>();
    if !(2..=3).contains(&parts.len()) {
        return None;
    }
    let numbers = parts
        .iter()
        .map(|part| part.parse::<u64>().ok())
        .collect::<Option<Vec<_>>>()?;
    if numbers[1] >= 60 || (parts.len() == 3 && numbers[2] >= 60) {
        return None;
    }
    let seconds = if parts.len() == 2 {
        numbers[0].checked_mul(60)?.checked_add(numbers[1])?
    } else {
        numbers[0]
            .checked_mul(3600)?
            .checked_add(numbers[1].checked_mul(60)?)?
            .checked_add(numbers[2])?
    };
    seconds.checked_mul(1000)
}

fn article_chapter_text(value: &str) -> String {
    if !value.contains('<') {
        return value.replace("&nbsp;", " ");
    }
    let Ok(dom) = std::panic::catch_unwind(|| {
        parse_document(Dom::default(), Default::default())
            .from_utf8()
            .one(value.as_bytes())
    }) else {
        return value.replace("&nbsp;", " ");
    };
    let mut output = String::with_capacity(value.len());
    append_chapter_text(&dom.document, &mut output);
    output
}

fn append_chapter_text(handle: &Handle, output: &mut String) {
    match &handle.data {
        NodeData::Text { contents } => output.push_str(&contents.borrow()),
        NodeData::Element { name, .. } => {
            let tag = name.local.as_ref();
            if tag == "br" {
                output.push('\n');
                return;
            }
            for child in handle.children.borrow().iter() {
                append_chapter_text(child, output);
            }
            if matches!(
                tag,
                "p" | "div" | "li" | "dt" | "dd" | "section" | "article"
            ) {
                output.push('\n');
            }
        }
        _ => {
            for child in handle.children.borrow().iter() {
                append_chapter_text(child, output);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn legacy_audio_suffix_uses_bytes_for_duration_cover_and_chapters() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("enclosure-42.audio");
        let picture = [0xff, 0xd8, 0xff, 0xd9];
        let mut payload = vec![0u8];
        payload.extend_from_slice(b"image/jpeg");
        payload.extend_from_slice(&[0, 3, 0]);
        payload.extend_from_slice(&picture);
        let mut frame = b"APIC".to_vec();
        frame.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        frame.extend_from_slice(&[0, 0]);
        frame.extend_from_slice(&payload);
        frame.extend(chapter_frame("intro", 0, 0, Some(100), "Intro"));
        let mut fixture = id3_fixture(&frame);
        fixture.extend(silent_mp3_frames(20));
        std::fs::write(&path, fixture).unwrap();

        let analyzed = analyze_file(&path);
        assert_eq!(analyzed.artwork, Some(picture.to_vec()));
        assert!(
            analyzed.duration_ms.is_some_and(|value| value >= 200),
            "{analyzed:?}"
        );
        assert_eq!(analyzed.embedded_chapters[0].title, "Intro");
        assert_eq!(analyzed.embedded_chapters[0].start_ms, 0);
    }

    #[test]
    fn mp4_cover_fallback_and_corrupt_media_fail_softly() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("podcast.audio");
        let picture = [0xff, 0xd8, 0xff, 0xd9];
        let mut data = Vec::new();
        data.extend_from_slice(&((16 + picture.len()) as u32).to_be_bytes());
        data.extend_from_slice(b"data");
        data.extend_from_slice(&[0; 8]);
        data.extend_from_slice(&picture);
        let mut cover = Vec::new();
        cover.extend_from_slice(&((8 + data.len()) as u32).to_be_bytes());
        cover.extend_from_slice(b"covr");
        cover.extend_from_slice(&data);
        std::fs::write(&path, cover).unwrap();
        assert_eq!(analyze_file(&path).artwork, Some(picture.to_vec()));

        std::fs::write(&path, b"not a media stream").unwrap();
        assert_eq!(analyze_file(&path), AnalyzedMedia::default());
    }

    #[test]
    fn article_timestamps_are_ordered_and_bounded() {
        let chapters = article_chapters(
            "00:00 Intro\n03:42 Topic One\n15:10 Topic Two",
            Some(20 * 60 * 1000),
        );
        assert_eq!(chapters.len(), 3);
        assert_eq!(chapters[1].start_ms, 222_000);
        assert_eq!(chapters[0].end_ms, Some(222_000));
        assert_eq!(chapters[2].end_ms, Some(1_200_000));
    }

    #[test]
    fn invalid_timestamps_and_traversal_references_are_ignored() {
        assert!(article_chapters("99:99 Not a chapter\n123 unrelated", None).is_empty());
        assert!(article_chapters("The meeting starts at 03:42 and ends later.", None).is_empty());
        assert!(article_chapters("03:42", None).is_empty());
        assert!(resolve_media_reference(Path::new("/media"), "../outside.mp3").is_none());
        assert!(resolve_media_reference(Path::new("/media"), "/tmp/file.mp3").is_none());
    }

    #[test]
    fn article_chapters_preserve_common_html_boundaries() {
        for html in [
            "<p>00:00 Intro</p><p>03:42 Topic</p>",
            "<div>00:00 Intro</div><div>03:42 Topic</div>",
            "00:00 Intro<br>03:42 Topic",
            "<ul><li>00:00 Intro</li><li>03:42 Topic</li></ul>",
        ] {
            let chapters = article_chapters(html, None);
            assert_eq!(chapters.len(), 2, "{html}");
            assert_eq!(chapters[0].title, "Intro", "{html}");
            assert_eq!(chapters[1].title, "Topic", "{html}");
        }
    }

    #[test]
    fn article_chapters_deduplicate_timestamps_deterministically() {
        let chapters = article_chapters(
            "<p>03:42 First</p><p>00:00 Intro</p><p>03:42 Duplicate</p>",
            None,
        );
        assert_eq!(chapters.len(), 2);
        assert_eq!(chapters[1].title, "First");
        assert_eq!(chapters[0].end_ms, Some(222_000));
    }

    #[test]
    fn long_form_timestamps_allow_unbounded_minutes_but_validate_seconds() {
        assert_eq!(parse_timestamp("60:00"), Some(3_600_000));
        assert_eq!(parse_timestamp("75:30"), Some(4_530_000));
        assert_eq!(parse_timestamp("1:15:30"), Some(4_530_000));
        assert_eq!(parse_timestamp("1:23:75"), None);
        assert_eq!(parse_timestamp("75:99"), None);
        assert_eq!(
            article_chapters("60:00 Long intro\n75:30 Topic", None)[0].start_ms,
            3_600_000
        );
    }

    #[test]
    fn id3_chap_frames_are_structured_and_malformed_frames_fail_softly() {
        let mut frames = chapter_frame("one", 0, 30_000, Some(25_000), "Intro");
        frames.extend_from_slice(&malformed_oversized_frame());
        frames.extend(chapter_frame("two", 30_000, 90_000, None, "Topic"));
        let fixture = id3_fixture(&frames);
        let chapters = parse_id3_chapters(&fixture);
        assert_eq!(chapters.len(), 2);
        assert_eq!(chapters[0].title, "Intro");
        assert_eq!(chapters[0].end_ms, Some(25_000));
        assert_eq!(chapters[1].start_ms, 30_000);
        assert_eq!(chapters[1].title, "Topic");
    }

    #[test]
    fn missing_chap_end_is_derived_and_oversized_frames_terminate_safely() {
        let mut frames = chapter_frame("one", 0, 30_000, None, "Intro");
        frames.extend(chapter_frame("two", 30_000, 60_000, Some(60_000), "Topic"));
        let chapters = parse_id3_chapters(&id3_fixture(&frames));
        assert_eq!(chapters[0].end_ms, Some(30_000));
        let malformed_end = [
            chapter_frame("bad", 30_000, 0, Some(20_000), "Bad boundary"),
            chapter_frame("good", 40_000, 0, Some(60_000), "Good"),
        ]
        .concat();
        let chapters = parse_id3_chapters(&id3_fixture(&malformed_end));
        assert_eq!(chapters[0].title, "Bad boundary");
        assert_eq!(chapters[0].end_ms, Some(40_000));
        assert!(parse_id3_chapters(&id3_fixture(&malformed_oversized_frame())).is_empty());
    }

    fn malformed_oversized_frame() -> Vec<u8> {
        let mut frame = b"JUNK".to_vec();
        frame.extend_from_slice(&u32::MAX.to_be_bytes());
        frame.extend_from_slice(&[0, 0]);
        frame
    }

    fn chapter_frame(
        id: &str,
        start: u32,
        _end: u32,
        explicit_end: Option<u32>,
        title: &str,
    ) -> Vec<u8> {
        let mut payload = id.as_bytes().to_vec();
        payload.push(0);
        payload.extend_from_slice(&start.to_be_bytes());
        payload.extend_from_slice(&explicit_end.unwrap_or(u32::MAX).to_be_bytes());
        payload.extend_from_slice(&0u32.to_be_bytes());
        payload.extend_from_slice(&0u32.to_be_bytes());
        let mut title_frame = b"TIT2".to_vec();
        let text = [vec![3], title.as_bytes().to_vec()].concat();
        title_frame.extend_from_slice(&(text.len() as u32).to_be_bytes());
        title_frame.extend_from_slice(&[0, 0]);
        title_frame.extend_from_slice(&text);
        payload.extend_from_slice(&title_frame);
        let mut frame = b"CHAP".to_vec();
        frame.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        frame.extend_from_slice(&[0, 0]);
        frame.extend_from_slice(&payload);
        frame
    }

    fn id3_fixture(frames: &[u8]) -> Vec<u8> {
        let size = frames.len();
        let mut fixture = b"ID3\x03\x00\x00".to_vec();
        fixture.extend_from_slice(&[
            (size >> 21) as u8,
            (size >> 14) as u8 & 0x7f,
            (size >> 7) as u8 & 0x7f,
            size as u8 & 0x7f,
        ]);
        fixture.extend_from_slice(frames);
        fixture
    }

    fn silent_mp3_frames(count: usize) -> Vec<u8> {
        // MPEG-1 Layer III, 128 kbit/s, 44.1 kHz. The demuxer only needs
        // structurally valid frames to determine duration; audio is not decoded.
        let mut frame = vec![0; 417];
        frame[..4].copy_from_slice(&[0xff, 0xfb, 0x90, 0x64]);
        frame.repeat(count)
    }
}
