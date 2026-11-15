use html5ever::{parse_document, tendril::TendrilSink};

use crate::domain::{
    DetailRenderingMode, ReaderBlock, ReaderDocument, ReaderInline, ReaderListItem,
};
use crate::html_dom::{Dom, Handle, NodeData};

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ArticleDocument {
    blocks: Vec<ReaderBlock>,
    has_simplified_content: bool,
}

const IGNORED: &[&str] = &[
    "head", "noscript", "script", "style", "template", "svg", "canvas", "form", "input",
];
const WRAPPERS: &[&str] = &[
    "article",
    "body",
    "html",
    "div",
    "figure",
    "figcaption",
    "main",
    "section",
    "span",
    "header",
    "footer",
    "aside",
    "details",
    "summary",
];

pub(crate) fn parse(html: &str, article_url: &str) -> ArticleDocument {
    if !contains_html_markup(html) {
        return ArticleDocument {
            blocks: text_block(html),
            has_simplified_content: false,
        };
    }
    let base = url::Url::parse(article_url).ok();
    let dom = match std::panic::catch_unwind(|| {
        parse_document(Dom::default(), Default::default())
            .from_utf8()
            .one(html.as_bytes())
    }) {
        Ok(dom) => dom,
        Err(_) => {
            return ArticleDocument {
                blocks: text_block(html),
                has_simplified_content: true,
            };
        }
    };
    let mut simplified = false;
    let blocks = blocks_from_children(
        &dom.document.children.borrow(),
        base.as_ref(),
        &mut simplified,
    );
    ArticleDocument {
        blocks,
        has_simplified_content: simplified,
    }
}

#[cfg(test)]
pub(crate) fn project(
    document: ArticleDocument,
    mode: DetailRenderingMode,
    limit: Option<u32>,
) -> ReaderDocument {
    project_with_fallback_image(document, mode, limit, None)
}

pub(crate) fn project_with_fallback_image(
    document: ArticleDocument,
    mode: DetailRenderingMode,
    limit: Option<u32>,
    fallback_image_url: Option<&str>,
) -> ReaderDocument {
    let mut blocks = project_blocks(document.blocks, mode);
    if mode == DetailRenderingMode::Rendered
        && !contains_image(&blocks)
        && fallback_image_url.is_some_and(valid_image_url)
    {
        blocks.insert(
            0,
            ReaderBlock::Image {
                url: fallback_image_url.expect("checked above").to_string(),
                alt: None,
                link: None,
            },
        );
    }
    let (blocks, was_truncated) = if let Some(limit) = limit {
        truncate(blocks, limit)
    } else {
        (blocks, false)
    };
    ReaderDocument {
        blocks,
        has_simplified_content: document.has_simplified_content,
        was_truncated,
    }
}

fn contains_image(blocks: &[ReaderBlock]) -> bool {
    blocks.iter().any(|block| match block {
        ReaderBlock::Image { .. } => true,
        ReaderBlock::List { items, .. } => items.iter().any(|item| contains_image(&item.blocks)),
        ReaderBlock::Quote { blocks } => contains_image(blocks),
        _ => false,
    })
}

fn valid_image_url(value: &str) -> bool {
    url::Url::parse(value)
        .map(|url| matches!(url.scheme(), "http" | "https"))
        .unwrap_or(false)
}

fn blocks_from_children(
    children: &[Handle],
    base: Option<&url::Url>,
    simplified: &mut bool,
) -> Vec<ReaderBlock> {
    let mut blocks = Vec::new();
    let mut inline = Vec::new();
    for child in children {
        match element_tag(child).as_deref() {
            Some(tag) if IGNORED.contains(&tag) => {}
            Some("p") => {
                flush_inline(&mut blocks, &mut inline);
                blocks.extend(content_blocks(child, base));
            }
            Some(tag) if matches!(tag, "h1" | "h2" | "h3" | "h4" | "h5" | "h6") => {
                flush_inline(&mut blocks, &mut inline);
                push_text_block(&mut blocks, inlines(child, base));
                if let Some(ReaderBlock::Paragraph { inlines }) = blocks.pop() {
                    blocks.push(ReaderBlock::Heading {
                        level: tag[1..].parse().unwrap_or(1),
                        inlines,
                    });
                }
            }
            Some("img") => {
                flush_inline(&mut blocks, &mut inline);
                if let Some(url) = image_url(child, base) {
                    blocks.push(ReaderBlock::Image {
                        url,
                        alt: attr(child, "alt"),
                        link: None,
                    });
                }
            }
            Some("a") if image_child(child).is_some() => {
                flush_inline(&mut blocks, &mut inline);
                let image = image_child(child).expect("checked above");
                if let Some(url) = image_url(&image, base) {
                    blocks.push(ReaderBlock::Image {
                        url,
                        alt: attr(&image, "alt"),
                        link: resolved_attr(child, "href", base),
                    });
                }
            }
            Some("ul") | Some("ol") => {
                flush_inline(&mut blocks, &mut inline);
                blocks.push(list(child, base, simplified));
            }
            Some("blockquote") => {
                flush_inline(&mut blocks, &mut inline);
                blocks.push(ReaderBlock::Quote {
                    blocks: blocks_from_children(&child.children.borrow(), base, simplified),
                });
            }
            Some("pre") => {
                flush_inline(&mut blocks, &mut inline);
                let text = text_content(child);
                if !text.trim().is_empty() {
                    blocks.push(ReaderBlock::CodeBlock { text });
                }
            }
            Some("hr") => {
                flush_inline(&mut blocks, &mut inline);
                blocks.push(ReaderBlock::HorizontalRule);
            }
            Some("iframe") | Some("embed") | Some("object") | Some("video") | Some("audio") => {
                flush_inline(&mut blocks, &mut inline);
                *simplified = true;
                if let Some(url) =
                    resolved_attr(child, "src", base).or_else(|| resolved_attr(child, "data", base))
                {
                    blocks.push(ReaderBlock::ExternalContent {
                        url,
                        label: Some("External content".into()),
                    });
                }
            }
            Some("table") => {
                flush_inline(&mut blocks, &mut inline);
                *simplified = true;
                push_text_block(&mut blocks, inlines(child, base));
                blocks.extend(table_images(child, base));
            }
            Some(tag) if WRAPPERS.contains(&tag) => {
                flush_inline(&mut blocks, &mut inline);
                blocks.extend(blocks_from_children(
                    &child.children.borrow(),
                    base,
                    simplified,
                ));
            }
            _ if has_block_child(child) => {
                flush_inline(&mut blocks, &mut inline);
                blocks.extend(blocks_from_children(
                    &child.children.borrow(),
                    base,
                    simplified,
                ));
            }
            _ => append_inlines(&mut inline, inlines(child, base)),
        }
    }
    flush_inline(&mut blocks, &mut inline);
    blocks
}

fn list(node: &Handle, base: Option<&url::Url>, simplified: &mut bool) -> ReaderBlock {
    let ordered = element_tag(node).as_deref() == Some("ol");
    let items = node
        .children
        .borrow()
        .iter()
        .filter(|child| element_tag(child).as_deref() == Some("li"))
        .map(|child| ReaderListItem {
            blocks: blocks_from_children(&child.children.borrow(), base, simplified),
        })
        .filter(|item| !item.blocks.is_empty())
        .collect();
    ReaderBlock::List { ordered, items }
}

fn content_blocks(node: &Handle, base: Option<&url::Url>) -> Vec<ReaderBlock> {
    let mut blocks = Vec::new();
    let mut inline = Vec::new();
    for child in node.children.borrow().iter() {
        if element_tag(child).as_deref() == Some("img") {
            flush_inline(&mut blocks, &mut inline);
            if let Some(image) = image_block(child, None, base) {
                blocks.push(image);
            }
        } else if element_tag(child).as_deref() == Some("a") && image_child(child).is_some() {
            flush_inline(&mut blocks, &mut inline);
            let image = image_child(child).expect("checked above");
            if let Some(image) = image_block(&image, resolved_attr(child, "href", base), base) {
                blocks.push(image);
            }
        } else {
            append_inlines(&mut inline, inline_node(child, base));
        }
    }
    flush_inline(&mut blocks, &mut inline);
    blocks
}

fn image_block(
    node: &Handle,
    link: Option<String>,
    base: Option<&url::Url>,
) -> Option<ReaderBlock> {
    image_url(node, base).map(|url| ReaderBlock::Image {
        url,
        alt: attr(node, "alt"),
        link,
    })
}

fn inlines(node: &Handle, base: Option<&url::Url>) -> Vec<ReaderInline> {
    let mut out = Vec::new();
    for child in node.children.borrow().iter() {
        append_inlines(&mut out, inline_node(child, base));
    }
    out
}

fn inline_node(node: &Handle, base: Option<&url::Url>) -> Vec<ReaderInline> {
    match &node.data {
        NodeData::Text { contents } => vec![ReaderInline::Text {
            text: contents.borrow().to_string(),
        }],
        NodeData::Element { name, .. } => match name.local.as_ref() {
            tag if IGNORED.contains(&tag) || tag == "img" => vec![],
            "br" => vec![ReaderInline::Text { text: "\n".into() }],
            "strong" | "b" => vec![ReaderInline::Bold {
                inlines: inlines(node, base),
            }],
            "em" | "i" => vec![ReaderInline::Italic {
                inlines: inlines(node, base),
            }],
            "code" => vec![ReaderInline::Code {
                text: text_content(node),
            }],
            "a" => {
                let children = inlines(node, base);
                match resolved_attr(node, "href", base) {
                    Some(url) => vec![ReaderInline::Link {
                        url,
                        inlines: children,
                    }],
                    None => children,
                }
            }
            _ => inlines(node, base),
        },
        _ => inlines(node, base),
    }
}

fn project_blocks(blocks: Vec<ReaderBlock>, mode: DetailRenderingMode) -> Vec<ReaderBlock> {
    blocks
        .into_iter()
        .filter_map(|block| match block {
            ReaderBlock::Image { .. } if mode == DetailRenderingMode::TextOnly => None,
            ReaderBlock::Paragraph { inlines } => Some(ReaderBlock::Paragraph {
                inlines: project_inlines(inlines, mode),
            }),
            ReaderBlock::Heading { level, inlines } => Some(ReaderBlock::Heading {
                level,
                inlines: project_inlines(inlines, mode),
            }),
            ReaderBlock::List { ordered, items } => Some(ReaderBlock::List {
                ordered,
                items: items
                    .into_iter()
                    .map(|item| ReaderListItem {
                        blocks: project_blocks(item.blocks, mode),
                    })
                    .collect(),
            }),
            ReaderBlock::Quote { blocks } => Some(ReaderBlock::Quote {
                blocks: project_blocks(blocks, mode),
            }),
            other => Some(other),
        })
        .collect()
}

fn project_inlines(inlines: Vec<ReaderInline>, mode: DetailRenderingMode) -> Vec<ReaderInline> {
    if mode == DetailRenderingMode::Rendered {
        return inlines;
    }
    let mut projected = Vec::new();
    for inline in inlines {
        match inline {
            ReaderInline::Text { .. } => projected.push(inline),
            ReaderInline::Bold { inlines } | ReaderInline::Italic { inlines } => {
                append_inlines(&mut projected, project_inlines(inlines, mode));
            }
            ReaderInline::Code { text } => {
                append_inlines(&mut projected, vec![ReaderInline::Text { text }])
            }
            ReaderInline::Link { inlines, .. } => {
                append_inlines(&mut projected, project_inlines(inlines, mode));
            }
        }
    }
    projected
}

fn truncate(blocks: Vec<ReaderBlock>, limit: u32) -> (Vec<ReaderBlock>, bool) {
    let mut remaining = limit as usize;
    let mut result = Vec::new();
    for block in blocks {
        if remaining == 0 {
            return (result, true);
        }
        let count = block_text_len(&block);
        if count <= remaining {
            remaining -= count;
            result.push(block);
            continue;
        }
        if remaining > 0
            && let Some(block) = truncate_block(block, remaining)
        {
            result.push(block);
        }
        return (result, true);
    }
    (result, false)
}

fn truncate_block(block: ReaderBlock, limit: usize) -> Option<ReaderBlock> {
    match block {
        ReaderBlock::Paragraph { inlines } => {
            truncate_inlines(inlines, limit).map(|inlines| ReaderBlock::Paragraph { inlines })
        }
        ReaderBlock::Heading { level, inlines } => {
            truncate_inlines(inlines, limit).map(|inlines| ReaderBlock::Heading { level, inlines })
        }
        ReaderBlock::CodeBlock { text } => Some(ReaderBlock::CodeBlock {
            text: cut_text(&text, limit),
        }),
        ReaderBlock::Quote { blocks } => {
            let (blocks, _) = truncate(blocks, limit as u32);
            (!blocks.is_empty()).then_some(ReaderBlock::Quote { blocks })
        }
        ReaderBlock::List { ordered, items } => {
            let mut remaining = limit;
            let mut kept = Vec::new();
            for item in items {
                let count: usize = item.blocks.iter().map(block_text_len).sum();
                if count <= remaining {
                    remaining -= count;
                    kept.push(item);
                } else {
                    let (blocks, _) = truncate(item.blocks, remaining as u32);
                    if !blocks.is_empty() {
                        kept.push(ReaderListItem { blocks });
                    }
                    break;
                }
            }
            (!kept.is_empty()).then_some(ReaderBlock::List {
                ordered,
                items: kept,
            })
        }
        other => Some(other),
    }
}

fn truncate_inlines(inlines: Vec<ReaderInline>, limit: usize) -> Option<Vec<ReaderInline>> {
    let mut remaining = limit;
    let mut result = Vec::new();
    for inline in inlines {
        let count = inline_text_len(&inline);
        if count <= remaining {
            remaining -= count;
            result.push(inline);
            continue;
        }
        if remaining > 0 {
            result.push(truncate_inline(inline, remaining));
        }
        break;
    }
    (!result.is_empty()).then_some(result)
}

fn truncate_inline(inline: ReaderInline, limit: usize) -> ReaderInline {
    match inline {
        ReaderInline::Text { text } => ReaderInline::Text {
            text: cut_text(&text, limit),
        },
        ReaderInline::Code { text } => ReaderInline::Code {
            text: cut_text(&text, limit),
        },
        ReaderInline::Bold { inlines } => ReaderInline::Bold {
            inlines: truncate_inlines(inlines, limit).unwrap_or_default(),
        },
        ReaderInline::Italic { inlines } => ReaderInline::Italic {
            inlines: truncate_inlines(inlines, limit).unwrap_or_default(),
        },
        ReaderInline::Link { url, inlines } => ReaderInline::Link {
            url,
            inlines: truncate_inlines(inlines, limit).unwrap_or_default(),
        },
    }
}

fn block_text_len(block: &ReaderBlock) -> usize {
    match block {
        ReaderBlock::Paragraph { inlines } | ReaderBlock::Heading { inlines, .. } => {
            inlines.iter().map(inline_text_len).sum()
        }
        ReaderBlock::List { items, .. } => items
            .iter()
            .flat_map(|item| &item.blocks)
            .map(block_text_len)
            .sum(),
        ReaderBlock::Quote { blocks } => blocks.iter().map(block_text_len).sum(),
        ReaderBlock::CodeBlock { text } => text.chars().count(),
        ReaderBlock::Image { .. }
        | ReaderBlock::HorizontalRule
        | ReaderBlock::ExternalContent { .. } => 0,
    }
}

fn inline_text_len(inline: &ReaderInline) -> usize {
    match inline {
        ReaderInline::Text { text } | ReaderInline::Code { text } => text.chars().count(),
        ReaderInline::Bold { inlines }
        | ReaderInline::Italic { inlines }
        | ReaderInline::Link { inlines, .. } => inlines.iter().map(inline_text_len).sum(),
    }
}

fn cut_text(text: &str, limit: usize) -> String {
    let exact: String = text.chars().take(limit).collect();
    if exact.chars().count() == text.chars().count() {
        return exact;
    }
    match exact.rsplit_once(char::is_whitespace) {
        Some((before, _)) => before.trim_end().into(),
        None => exact,
    }
}

fn flush_inline(blocks: &mut Vec<ReaderBlock>, inline: &mut Vec<ReaderInline>) {
    if !inline.is_empty() {
        push_text_block(blocks, std::mem::take(inline));
    }
}
fn push_text_block(blocks: &mut Vec<ReaderBlock>, inlines: Vec<ReaderInline>) {
    if !inline_text(&inlines).trim().is_empty() {
        blocks.push(ReaderBlock::Paragraph { inlines });
    }
}
fn append_inlines(out: &mut Vec<ReaderInline>, mut added: Vec<ReaderInline>) {
    if let (Some(ReaderInline::Text { text: left }), Some(ReaderInline::Text { text: right })) =
        (out.last_mut(), added.first_mut())
    {
        left.push_str(right);
        added.remove(0);
    }
    out.extend(added);
}
fn inline_text(inlines: &[ReaderInline]) -> String {
    inlines
        .iter()
        .map(|inline| match inline {
            ReaderInline::Text { text } | ReaderInline::Code { text } => text.clone(),
            ReaderInline::Bold { inlines }
            | ReaderInline::Italic { inlines }
            | ReaderInline::Link { inlines, .. } => inline_text(inlines),
        })
        .collect()
}
fn text_block(text: &str) -> Vec<ReaderBlock> {
    (!text.trim().is_empty())
        .then_some(ReaderBlock::Paragraph {
            inlines: vec![ReaderInline::Text { text: text.into() }],
        })
        .into_iter()
        .collect()
}
fn contains_html_markup(input: &str) -> bool {
    let bytes = input.as_bytes();
    for (index, _) in input.char_indices() {
        if bytes[index] != b'<' {
            continue;
        }
        let remainder = &input[index..];
        if remainder.starts_with("<!--") {
            if remainder.contains("-->") {
                return true;
            }
        } else if remainder
            .get(..9)
            .is_some_and(|prefix| prefix.eq_ignore_ascii_case("<!doctype"))
        {
            if remainder
                .as_bytes()
                .get(9)
                .is_some_and(|byte| byte.is_ascii_whitespace() || *byte == b'>')
                && remainder.contains('>')
            {
                return true;
            }
        } else if let Some(tag) = remainder.strip_prefix("</") {
            if tag.as_bytes().first().is_some_and(u8::is_ascii_alphabetic)
                && tag.find('>').is_some_and(|end| !tag[..end].contains('<'))
            {
                return true;
            }
        } else if let Some(first) = remainder.as_bytes().get(1) {
            let after_open = &remainder[1..];
            if first.is_ascii_alphabetic()
                && after_open
                    .find('>')
                    .is_some_and(|end| !after_open[..end].contains('<'))
            {
                return true;
            }
        }
    }
    false
}
fn text_content(node: &Handle) -> String {
    inline_text(&inlines(node, None))
}
fn element_tag(node: &Handle) -> Option<String> {
    match &node.data {
        NodeData::Element { name, .. } => Some(name.local.to_string()),
        _ => None,
    }
}
fn image_child(node: &Handle) -> Option<Handle> {
    node.children
        .borrow()
        .iter()
        .find(|child| element_tag(child).as_deref() == Some("img"))
        .cloned()
}
fn has_block_child(node: &Handle) -> bool {
    node.children.borrow().iter().any(|child| {
        matches!(
            element_tag(child).as_deref(),
            Some(
                "p" | "h1"
                    | "h2"
                    | "h3"
                    | "h4"
                    | "h5"
                    | "h6"
                    | "img"
                    | "ul"
                    | "ol"
                    | "blockquote"
                    | "pre"
                    | "hr"
                    | "iframe"
                    | "embed"
                    | "object"
                    | "video"
                    | "audio"
                    | "table"
            )
        )
    })
}
fn table_images(node: &Handle, base: Option<&url::Url>) -> Vec<ReaderBlock> {
    let mut images = Vec::new();
    collect_table_images(node, None, base, &mut images);
    images
}
fn collect_table_images(
    node: &Handle,
    enclosing_link: Option<String>,
    base: Option<&url::Url>,
    images: &mut Vec<ReaderBlock>,
) {
    let link = if element_tag(node).as_deref() == Some("a") {
        resolved_attr(node, "href", base).or(enclosing_link)
    } else {
        enclosing_link
    };
    if element_tag(node).as_deref() == Some("img") {
        if let Some(image) = image_block(node, link, base) {
            images.push(image);
        }
        return;
    }
    for child in node.children.borrow().iter() {
        collect_table_images(child, link.clone(), base, images);
    }
}
fn attr(node: &Handle, key: &str) -> Option<String> {
    match &node.data {
        NodeData::Element { attrs, .. } => attrs
            .borrow()
            .iter()
            .find(|attribute| <_ as AsRef<str>>::as_ref(&attribute.name.local) == key)
            .map(|attribute| attribute.value.trim().to_string())
            .filter(|value| !value.is_empty()),
        _ => None,
    }
}
fn resolved_attr(node: &Handle, key: &str, base: Option<&url::Url>) -> Option<String> {
    let value = attr(node, key)?;
    if value.to_ascii_lowercase().starts_with("data:") {
        return None;
    }
    url::Url::parse(&value)
        .or_else(|_| {
            base.ok_or(url::ParseError::RelativeUrlWithoutBase)
                .and_then(|base| base.join(&value))
        })
        .ok()
        .filter(|url| matches!(url.scheme(), "http" | "https"))
        .map(|url| url.to_string())
}
fn image_url(node: &Handle, base: Option<&url::Url>) -> Option<String> {
    ["data-src", "data-original", "src"]
        .into_iter()
        .find_map(|key| resolved_attr(node, key, base))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parser_preserves_supported_semantics_and_simplifies_embeds() {
        let document = parse(
            "<h2>Title <em>here</em></h2><p>A <strong>bold</strong> <a href=\"/link\">link</a>.</p><a href=\"/original\"><img src=\"/image.jpg\" alt=\"Image\"></a><ol><li>One<ul><li>Nested</li></ul></li></ol><blockquote><p>Quote</p></blockquote><pre>let x = 1;</pre><hr><iframe src=\"https://embed.test/x\"></iframe>",
            "https://example.test/post",
        );
        assert!(document.has_simplified_content);
        assert!(matches!(
            document.blocks[0],
            ReaderBlock::Heading { level: 2, .. }
        ));
        assert!(
            matches!(document.blocks[2], ReaderBlock::Image { ref url, link: Some(ref link), .. } if url == "https://example.test/image.jpg" && link == "https://example.test/original")
        );
        assert!(matches!(
            document.blocks[3],
            ReaderBlock::List { ordered: true, .. }
        ));
        assert!(matches!(document.blocks[4], ReaderBlock::Quote { .. }));
        assert!(matches!(document.blocks[5], ReaderBlock::CodeBlock { .. }));
        assert!(matches!(document.blocks[6], ReaderBlock::HorizontalRule));
        assert!(matches!(
            document.blocks[7],
            ReaderBlock::ExternalContent { .. }
        ));
    }

    #[test]
    fn text_only_omits_images_but_keeps_link_text() {
        let rendered = project(
            parse(
                "<p><a href=\"/link\">Read this</a></p><img src=\"/image.jpg\">",
                "https://example.test/post",
            ),
            DetailRenderingMode::TextOnly,
            None,
        );
        assert_eq!(rendered.blocks.len(), 1);
        assert!(
            matches!(&rendered.blocks[0], ReaderBlock::Paragraph { inlines } if inline_text(inlines) == "Read this" && inlines.iter().all(|inline| matches!(inline, ReaderInline::Text { .. })))
        );
    }

    #[test]
    fn rendered_projection_uses_enclosure_derived_image_as_fallback() {
        let persisted_image = crate::article::process(
            "<p>Article text</p>",
            "https://example.test/post",
            &[crate::article::EnclosureInput {
                url: "/cover.jpg".into(),
                mime_type: "image/jpeg".into(),
            }],
        )
        .image_url;
        let document = project_with_fallback_image(
            parse("<p>Article text</p>", "https://example.test/post"),
            DetailRenderingMode::Rendered,
            None,
            persisted_image.as_deref(),
        );

        assert!(
            matches!(&document.blocks[..], [ReaderBlock::Image { url, alt: None, link: None }, ReaderBlock::Paragraph { .. }] if url == "https://example.test/cover.jpg")
        );
    }

    #[test]
    fn rendered_projection_prepends_persisted_image_without_html_image() {
        let document = project_with_fallback_image(
            parse("<p>Article text</p>", "https://example.test/post"),
            DetailRenderingMode::Rendered,
            None,
            Some("https://images.test/hero.jpg"),
        );

        assert!(
            matches!(&document.blocks[0], ReaderBlock::Image { url, alt: None, link: None } if url == "https://images.test/hero.jpg")
        );
    }

    #[test]
    fn rendered_projection_does_not_duplicate_html_or_nested_images() {
        let document = project_with_fallback_image(
            parse(
                "<p>Article text</p><img src=\"/html.jpg\">",
                "https://example.test/post",
            ),
            DetailRenderingMode::Rendered,
            None,
            Some("https://images.test/fallback.jpg"),
        );
        assert_eq!(
            document
                .blocks
                .iter()
                .filter(|block| matches!(block, ReaderBlock::Image { .. }))
                .count(),
            1
        );

        assert!(contains_image(&[ReaderBlock::Quote {
            blocks: vec![ReaderBlock::List {
                ordered: false,
                items: vec![ReaderListItem {
                    blocks: vec![ReaderBlock::Image {
                        url: "https://images.test/nested.jpg".into(),
                        alt: None,
                        link: None,
                    }],
                }],
            }],
        }]));
    }

    #[test]
    fn text_only_projection_never_uses_persisted_image_fallback() {
        let document = project_with_fallback_image(
            parse("<p>Article text</p>", "https://example.test/post"),
            DetailRenderingMode::TextOnly,
            None,
            Some("https://images.test/hero.jpg"),
        );

        assert!(!contains_image(&document.blocks));
    }

    #[test]
    fn rendered_projection_without_any_image_remains_unchanged() {
        let parsed = parse("<p>Article text</p>", "https://example.test/post");
        assert_eq!(
            project(parsed.clone(), DetailRenderingMode::Rendered, None),
            project_with_fallback_image(parsed, DetailRenderingMode::Rendered, None, None)
        );
    }

    #[test]
    fn fallback_image_precedes_truncation_without_counting_as_text() {
        let document = project_with_fallback_image(
            parse("<p>One two three four</p>", "https://example.test/post"),
            DetailRenderingMode::Rendered,
            Some(7),
            Some("https://images.test/hero.jpg"),
        );

        assert!(document.was_truncated);
        assert!(
            matches!(&document.blocks[0], ReaderBlock::Image { url, .. } if url == "https://images.test/hero.jpg")
        );
        assert!(
            matches!(&document.blocks[1], ReaderBlock::Paragraph { inlines } if inline_text(inlines) == "One")
        );
    }

    #[test]
    fn plaintext_content_projects_as_a_paragraph_in_both_modes() {
        let content = "His performance as Frank-N-Furter, the cross-dressing mad scientist of “The Rocky Horror Picture Show,” was ahead of its time.";
        for mode in [DetailRenderingMode::Rendered, DetailRenderingMode::TextOnly] {
            let document = project(parse(content, "https://example.test/post"), mode, None);
            assert!(
                matches!(&document.blocks[..], [ReaderBlock::Paragraph { inlines }] if inline_text(inlines) == content)
            );
        }
    }

    #[test]
    fn plaintext_variants_do_not_require_html_markup() {
        for (input, expected) in [
            ("Simple plain text", "Simple plain text"),
            ("First line\nSecond line", "First line\nSecond line"),
            (
                "  Surrounded by whitespace  ",
                "  Surrounded by whitespace  ",
            ),
            ("A & B, 1 < 2, and 3 > 2", "A & B, 1 < 2, and 3 > 2"),
        ] {
            let document = parse(input, "https://example.test/post");
            assert!(
                matches!(&document.blocks[..], [ReaderBlock::Paragraph { inlines }] if inline_text(inlines) == expected)
            );
        }
        assert!(
            parse(" \n\t ", "https://example.test/post")
                .blocks
                .is_empty()
        );
    }

    #[test]
    fn plaintext_content_uses_existing_truncation() {
        let document = project(
            parse("One two three four", "https://example.test/post"),
            DetailRenderingMode::Rendered,
            Some(7),
        );
        assert!(document.was_truncated);
        assert!(
            matches!(&document.blocks[..], [ReaderBlock::Paragraph { inlines }] if inline_text(inlines) == "One")
        );
    }

    #[test]
    fn html_and_ignored_only_html_are_not_treated_as_plaintext() {
        let html = parse(
            "<p>Normal <strong>HTML</strong></p>",
            "https://example.test/post",
        );
        assert!(matches!(&html.blocks[..], [ReaderBlock::Paragraph { .. }]));
        assert!(
            parse(
                "<script>hidden()</script><style>.hidden {}</style>",
                "https://example.test/post"
            )
            .blocks
            .is_empty()
        );
    }

    #[test]
    fn rendered_projection_preserves_nested_inline_semantics() {
        let document = project(
            parse(
                "<p>Before <strong>bold <em>italic</em></strong> <a href=\"/link\"><strong>linked</strong></a> after <code>x &lt; y</code>.</p>",
                "https://example.test/post",
            ),
            DetailRenderingMode::Rendered,
            None,
        );
        let ReaderBlock::Paragraph { inlines } = &document.blocks[0] else {
            panic!("expected paragraph");
        };
        assert!(
            matches!(&inlines[1], ReaderInline::Bold { inlines } if matches!(&inlines[1], ReaderInline::Italic { .. }))
        );
        assert!(
            matches!(&inlines[3], ReaderInline::Link { url, inlines } if url == "https://example.test/link" && matches!(&inlines[0], ReaderInline::Bold { .. }))
        );
        assert!(
            inlines
                .iter()
                .any(|inline| matches!(inline, ReaderInline::Code { text } if text == "x < y"))
        );
    }

    #[test]
    fn malformed_wrappers_ignore_non_content_and_truncate_nested_blocks() {
        let document = project(
            parse(
                "<custom-wrap><p>Useful <span>text</span><script>bad()</script><style>.bad{}</style></p><blockquote><ul><li>First item</li><li>Second item</li></ul></blockquote><iframe></iframe>",
                "https://example.test/post",
            ),
            DetailRenderingMode::Rendered,
            Some(6),
        );
        assert!(document.has_simplified_content);
        assert!(document.was_truncated);
        assert!(matches!(document.blocks[0], ReaderBlock::Paragraph { .. }));
        assert!(
            inline_text(match &document.blocks[0] {
                ReaderBlock::Paragraph { inlines } => inlines,
                _ => unreachable!(),
            })
            .contains("Useful")
        );
        assert!(!format!("{:?}", document.blocks).contains("bad()"));
    }

    #[test]
    fn parser_preserves_images_nested_in_paragraphs() {
        let document = parse(
            "<p>Before <img src=\"/image.jpg\" alt=\"Image\"> after</p>",
            "https://example.test/post",
        );
        assert!(matches!(document.blocks[0], ReaderBlock::Paragraph { .. }));
        assert!(matches!(document.blocks[1], ReaderBlock::Image { .. }));
        assert!(matches!(document.blocks[2], ReaderBlock::Paragraph { .. }));
    }

    #[test]
    fn truncation_prefers_complete_blocks_and_cuts_large_blocks_at_words() {
        let document = project(
            parse(
                "<p>Short text</p><img src=\"/before.jpg\"><p>A very long sentence that continues.</p><p>After</p>",
                "https://example.test/",
            ),
            DetailRenderingMode::Rendered,
            Some(15),
        );
        assert!(document.was_truncated);
        assert_eq!(document.blocks.len(), 3);
        assert!(matches!(document.blocks[1], ReaderBlock::Image { .. }));
        assert_eq!(block_text_len(&document.blocks[2]), 1);
    }

    #[test]
    fn wordpress_fixture_preserves_content_and_simplifies_product_table() {
        let document = project_with_fallback_image(
            parse(
                include_str!("../tests/wordpress_reader_fixture.html"),
                "https://publisher.test/posts/grinders",
            ),
            DetailRenderingMode::Rendered,
            None,
            Some("https://images.test/fallback.jpg"),
        );
        assert!(document.has_simplified_content);
        assert!(document.blocks.iter().any(|block| matches!(block, ReaderBlock::Image { url, .. } if url == "https://publisher.test/images/lead.jpg")));
        let text = document
            .blocks
            .iter()
            .map(|block| match block {
                ReaderBlock::Paragraph { inlines } => inline_text(inlines),
                _ => String::new(),
            })
            .collect::<String>();
        assert!(text.contains("best coffee grinders"));
        assert!(text.contains("Grinder A"));
        assert!(text.contains("affiliate commission"));
        assert!(document.blocks.iter().any(|block| matches!(block, ReaderBlock::Image { link: Some(link), .. } if link == "https://shop.test/grinder-a")));
        assert!(!document.blocks.iter().any(|block| matches!(block, ReaderBlock::Image { url, .. } if url == "https://images.test/fallback.jpg")));

        let text_only = project(
            parse(
                include_str!("../tests/wordpress_reader_fixture.html"),
                "https://publisher.test/posts/grinders",
            ),
            DetailRenderingMode::TextOnly,
            Some(120),
        );
        assert!(text_only.was_truncated);
        assert!(
            !text_only
                .blocks
                .iter()
                .any(|block| matches!(block, ReaderBlock::Image { .. }))
        );
        let has_flat_paragraph = text_only.blocks.iter().any(|block| {
            matches!(block, ReaderBlock::Paragraph { inlines } if inlines.iter().all(|inline| matches!(inline, ReaderInline::Text { .. })))
        });
        assert!(has_flat_paragraph);
    }
}
