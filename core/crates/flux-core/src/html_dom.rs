//! Minimal owned HTML tree used by Flux's content extractors.
//!
//! `html5ever` deliberately leaves tree storage to its caller. Flux only needs a
//! static tree with element names, attributes, text, and ordered children, so it
//! keeps that narrow representation here instead of depending on the unsupported
//! test-only `markup5ever_rcdom` crate.

use std::borrow::Cow;
use std::cell::{Cell, RefCell};
use std::collections::HashSet;
use std::mem;
use std::rc::{Rc, Weak};

use html5ever::interface::tree_builder::{ElementFlags, NodeOrText, QuirksMode, TreeSink};
use html5ever::tendril::StrTendril;
use html5ever::{Attribute, QualName};

pub(crate) type Handle = Rc<Node>;

#[derive(Debug)]
pub(crate) enum NodeData {
    Document,
    Text {
        contents: RefCell<StrTendril>,
    },
    Element {
        name: QualName,
        attrs: RefCell<Vec<Attribute>>,
        template_contents: RefCell<Option<Handle>>,
        mathml_annotation_xml_integration_point: bool,
    },
    Other,
}

#[derive(Debug)]
pub(crate) struct Node {
    parent: RefCell<Option<Weak<Node>>>,
    pub(crate) children: RefCell<Vec<Handle>>,
    pub(crate) data: NodeData,
}

impl Node {
    fn new(data: NodeData) -> Handle {
        Rc::new(Self {
            parent: RefCell::new(None),
            children: RefCell::new(Vec::new()),
            data,
        })
    }

    fn detach(target: &Handle) {
        let parent = target.parent.borrow().as_ref().and_then(Weak::upgrade);
        if let Some(parent) = parent {
            parent
                .children
                .borrow_mut()
                .retain(|child| !Rc::ptr_eq(child, target));
        }
        *target.parent.borrow_mut() = None;
    }

    fn append(parent: &Handle, child: Handle) {
        Self::detach(&child);
        *child.parent.borrow_mut() = Some(Rc::downgrade(parent));
        parent.children.borrow_mut().push(child);
    }
}

impl Drop for Node {
    fn drop(&mut self) {
        // Avoid recursive destruction for adversarially deep documents.
        let mut pending = mem::take(self.children.get_mut());
        while let Some(node) = pending.pop() {
            if let Ok(mut children) = node.children.try_borrow_mut() {
                pending.extend(mem::take(&mut *children));
            }
            if let NodeData::Element {
                template_contents, ..
            } = &node.data
                && let Ok(mut contents) = template_contents.try_borrow_mut()
                && let Some(contents) = contents.take()
            {
                pending.push(contents);
            }
        }
    }
}

pub(crate) struct Dom {
    pub(crate) document: Handle,
    quirks_mode: Cell<QuirksMode>,
}

impl Default for Dom {
    fn default() -> Self {
        Self {
            document: Node::new(NodeData::Document),
            quirks_mode: Cell::new(QuirksMode::NoQuirks),
        }
    }
}

impl Dom {
    fn append_common(
        &self,
        parent: &Handle,
        insert_before: Option<&Handle>,
        child: NodeOrText<Handle>,
    ) {
        let children = parent.children.borrow_mut();
        let index = insert_before
            .and_then(|sibling| children.iter().position(|node| Rc::ptr_eq(node, sibling)))
            .unwrap_or(children.len());

        if let NodeOrText::AppendText(text) = &child
            && index > 0
            && let NodeData::Text { contents } = &children[index - 1].data
        {
            contents.borrow_mut().push_tendril(text);
            return;
        }

        let node = match child {
            NodeOrText::AppendText(contents) => Node::new(NodeData::Text {
                contents: RefCell::new(contents),
            }),
            NodeOrText::AppendNode(node) => node,
        };
        drop(children);
        Node::detach(&node);
        *node.parent.borrow_mut() = Some(Rc::downgrade(parent));
        parent.children.borrow_mut().insert(index, node);
    }
}

impl TreeSink for Dom {
    type Handle = Handle;
    type Output = Self;
    type ElemName<'a>
        = &'a QualName
    where
        Self: 'a;

    fn finish(self) -> Self {
        self
    }

    fn parse_error(&self, _message: Cow<'static, str>) {}

    fn get_document(&self) -> Handle {
        self.document.clone()
    }

    fn get_template_contents(&self, target: &Handle) -> Handle {
        match &target.data {
            NodeData::Element {
                template_contents, ..
            } => template_contents
                .borrow()
                .as_ref()
                .expect("template element has no contents")
                .clone(),
            _ => panic!("template contents requested for non-element"),
        }
    }

    fn set_quirks_mode(&self, mode: QuirksMode) {
        self.quirks_mode.set(mode);
    }

    fn same_node(&self, left: &Handle, right: &Handle) -> bool {
        Rc::ptr_eq(left, right)
    }

    fn elem_name<'a>(&self, target: &'a Handle) -> Self::ElemName<'a> {
        match &target.data {
            NodeData::Element { name, .. } => name,
            _ => panic!("element name requested for non-element"),
        }
    }

    fn is_mathml_annotation_xml_integration_point(&self, target: &Handle) -> bool {
        match &target.data {
            NodeData::Element {
                mathml_annotation_xml_integration_point,
                ..
            } => *mathml_annotation_xml_integration_point,
            _ => false,
        }
    }

    fn create_element(&self, name: QualName, attrs: Vec<Attribute>, flags: ElementFlags) -> Handle {
        Node::new(NodeData::Element {
            name,
            attrs: RefCell::new(attrs),
            template_contents: RefCell::new(flags.template.then(|| Node::new(NodeData::Document))),
            mathml_annotation_xml_integration_point: flags.mathml_annotation_xml_integration_point,
        })
    }

    fn create_comment(&self, _text: StrTendril) -> Handle {
        Node::new(NodeData::Other)
    }

    fn create_pi(&self, _target: StrTendril, _data: StrTendril) -> Handle {
        Node::new(NodeData::Other)
    }

    fn append(&self, parent: &Handle, child: NodeOrText<Handle>) {
        self.append_common(parent, None, child);
    }

    fn append_before_sibling(&self, sibling: &Handle, child: NodeOrText<Handle>) {
        let parent = sibling
            .parent
            .borrow()
            .as_ref()
            .and_then(Weak::upgrade)
            .expect("sibling has no parent");
        self.append_common(&parent, Some(sibling), child);
    }

    fn append_based_on_parent_node(
        &self,
        element: &Handle,
        previous_element: &Handle,
        child: NodeOrText<Handle>,
    ) {
        if element.parent.borrow().is_some() {
            self.append_before_sibling(element, child);
        } else {
            self.append(previous_element, child);
        }
    }

    fn append_doctype_to_document(
        &self,
        _name: StrTendril,
        _public_id: StrTendril,
        _system_id: StrTendril,
    ) {
        Node::append(&self.document, Node::new(NodeData::Other));
    }

    fn add_attrs_if_missing(&self, target: &Handle, attrs: Vec<Attribute>) {
        let NodeData::Element {
            attrs: existing, ..
        } = &target.data
        else {
            panic!("attributes added to non-element");
        };
        let mut existing = existing.borrow_mut();
        let names = existing
            .iter()
            .map(|attribute| attribute.name.clone())
            .collect::<HashSet<_>>();
        existing.extend(
            attrs
                .into_iter()
                .filter(|attribute| !names.contains(&attribute.name)),
        );
    }

    fn remove_from_parent(&self, target: &Handle) {
        Node::detach(target);
    }

    fn reparent_children(&self, node: &Handle, new_parent: &Handle) {
        let children = mem::take(&mut *node.children.borrow_mut());
        for child in children {
            *child.parent.borrow_mut() = None;
            Node::append(new_parent, child);
        }
    }
}
