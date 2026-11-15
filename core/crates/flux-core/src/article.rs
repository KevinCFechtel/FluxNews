use std::cell::RefCell;

use html5ever::{parse_document, tendril::TendrilSink};

use crate::html_dom::{Dom, Handle, NodeData};

pub const PROCESSING_VERSION: i64 = 1;
pub const PREVIEW_LIMIT: usize = 1000;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ProcessedArticleContent {
    pub preview: String,
    pub image_url: Option<String>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EnclosureInput {
    pub url: String,
    pub mime_type: String,
}

const IGNORED: &[&str] = &["head", "noscript", "script", "style", "template"];
const BLOCKS: &[&str] = &[
    "address",
    "article",
    "aside",
    "blockquote",
    "div",
    "figcaption",
    "figure",
    "footer",
    "h1",
    "h2",
    "h3",
    "h4",
    "h5",
    "h6",
    "header",
    "li",
    "main",
    "nav",
    "p",
    "pre",
    "section",
    "table",
    "td",
    "th",
    "tr",
];
const IMAGE_ATTRS: &[&str] = &["data-src", "data-original", "src", "data-srcset", "srcset"];

pub fn process(
    html: &str,
    article_url: &str,
    enclosures: &[EnclosureInput],
) -> ProcessedArticleContent {
    if html.trim().is_empty() {
        return ProcessedArticleContent::default();
    }
    let base = url::Url::parse(article_url).ok();
    let dom = match std::panic::catch_unwind(|| {
        parse_document(Dom::default(), Default::default())
            .from_utf8()
            .one(html.as_bytes())
    }) {
        Ok(dom) => dom,
        Err(_) => {
            return ProcessedArticleContent {
                preview: truncate(&collapse(html)),
                image_url: enclosure_image(enclosures, base.as_ref()),
            };
        }
    };
    let mut text = String::new();
    append_text(&mut text, &dom.document);
    let image_url = first_image(&dom.document, base.as_ref())
        .or_else(|| enclosure_image(enclosures, base.as_ref()));
    ProcessedArticleContent {
        preview: normalize(&text),
        image_url,
    }
}
fn append_text(out: &mut String, node: &Handle) {
    match &node.data {
        NodeData::Element { name, attrs, .. } => {
            let tag = name.local.as_ref();
            if IGNORED.contains(&tag) {
                return;
            }
            if tag == "br" {
                out.push('\n');
            } else if tag == "img"
                && let Some(alt) = attr(attrs, "alt")
            {
                out.push(' ');
                out.push_str(&alt);
                out.push(' ');
            }
            if BLOCKS.contains(&tag) {
                out.push('\n');
            }
            for child in node.children.borrow().iter() {
                append_text(out, child);
            }
            if BLOCKS.contains(&tag) {
                out.push('\n');
            }
        }
        NodeData::Text { contents } => out.push_str(&contents.borrow()),
        _ => {
            for child in node.children.borrow().iter() {
                append_text(out, child);
            }
        }
    }
}
fn normalize(value: &str) -> String {
    truncate(
        &value
            .split('\n')
            .map(collapse)
            .filter(|line| !line.is_empty())
            .collect::<Vec<_>>()
            .join("\n"),
    )
}
fn collapse(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}
fn truncate(value: &str) -> String {
    if value.chars().count() <= PREVIEW_LIMIT {
        value.into()
    } else {
        format!(
            "{}…",
            value
                .chars()
                .take(PREVIEW_LIMIT - 1)
                .collect::<String>()
                .trim_end()
        )
    }
}
fn first_image(node: &Handle, base: Option<&url::Url>) -> Option<String> {
    if let NodeData::Element { name, attrs, .. } = &node.data {
        let tag: &str = name.local.as_ref();
        if (tag == "img" || tag == "source") && !tiny(attrs) {
            for key in IMAGE_ATTRS {
                let candidate = attr(attrs, key).unwrap_or_default();
                let candidate = if key.ends_with("srcset") {
                    srcset(&candidate)
                } else {
                    candidate
                };
                if let Some(url) = resolve(&candidate, base) {
                    return Some(url);
                }
            }
        }
    }
    for child in node.children.borrow().iter() {
        if let Some(url) = first_image(child, base) {
            return Some(url);
        }
    }
    None
}
fn enclosure_image(items: &[EnclosureInput], base: Option<&url::Url>) -> Option<String> {
    items
        .iter()
        .find(|item| {
            item.mime_type
                .split(';')
                .next()
                .unwrap_or("")
                .trim()
                .to_ascii_lowercase()
                .starts_with("image/")
        })
        .and_then(|item| resolve(&item.url, base))
}
fn resolve(value: &str, base: Option<&url::Url>) -> Option<String> {
    let value = value.trim();
    if value.is_empty() || value.to_ascii_lowercase().starts_with("data:") {
        return None;
    }
    let url = url::Url::parse(value)
        .or_else(|_| {
            base.ok_or(url::ParseError::RelativeUrlWithoutBase)
                .and_then(|base| base.join(value))
        })
        .ok()?;
    matches!(url.scheme(), "http" | "https").then(|| url.to_string())
}
fn srcset(value: &str) -> String {
    value
        .split(',')
        .rev()
        .find_map(|part| part.split_whitespace().next())
        .unwrap_or("")
        .into()
}
fn tiny(attrs: &RefCell<Vec<html5ever::Attribute>>) -> bool {
    matches!((attr(attrs,"width").and_then(|v| dim(&v)), attr(attrs,"height").and_then(|v| dim(&v))), (Some(w),Some(h)) if w <= 2 && h <= 2)
}
fn dim(value: &str) -> Option<i32> {
    value
        .trim()
        .trim_end_matches("px")
        .trim()
        .parse()
        .ok()
        .filter(|v: &i32| *v >= 0)
}
fn attr(attrs: &RefCell<Vec<html5ever::Attribute>>, key: &str) -> Option<String> {
    attrs
        .borrow()
        .iter()
        .find(|attr| <_ as AsRef<str>>::as_ref(&attr.name.local) == key)
        .map(|attr| attr.value.trim().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn text_and_image_processing() {
        let result = process(
            "<html><head><title>x</title></head><body><p>A &amp; B<br>C</p><script>x</script><img width=\"1\" height=\"1\" src=\"x\"><img data-src=\"/a.jpg\" alt=\"Alt\"></body></html>",
            "https://x.test/post",
            &[],
        );
        assert_eq!(result.preview, "A & B\nC\nAlt");
        assert_eq!(result.image_url.as_deref(), Some("https://x.test/a.jpg"));
    }
    #[test]
    fn unicode_srcset_and_enclosure() {
        let result = process(
            &format!(
                "<source srcset=\"a.jpg 1x, //cdn.test/b.jpg 2x\"><p>{}</p>",
                "ä".repeat(1001)
            ),
            "https://x.test/",
            &[],
        );
        assert_eq!(result.preview.chars().count(), 1000);
        assert!(result.preview.ends_with('…'));
        assert_eq!(result.image_url.as_deref(), Some("https://cdn.test/b.jpg"));
        let result = process(
            "<img src=\"data:x\">",
            "https://x.test/",
            &[EnclosureInput {
                url: "/cover.jpg".into(),
                mime_type: "image/jpeg".into(),
            }],
        );
        assert_eq!(
            result.image_url.as_deref(),
            Some("https://x.test/cover.jpg")
        );
    }
}
