use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use tracing::field::{Field, Visit};
use tracing::{Event, Level, Subscriber};
use tracing_subscriber::Layer;
use tracing_subscriber::layer::SubscriberExt;

const MAX_PENDING_RECORDS: usize = 128;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DiagnosticLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DiagnosticRecord {
    pub level: DiagnosticLevel,
    pub target: String,
    pub message: String,
}

pub trait CoreDiagnosticListener: Send + Sync {
    fn on_diagnostic(&self, record: DiagnosticRecord);
}

pub struct Diagnostics {
    listeners: Mutex<HashMap<u64, Arc<dyn CoreDiagnosticListener>>>,
    pending: Mutex<VecDeque<DiagnosticRecord>>,
    next_listener_id: AtomicU64,
}

impl Diagnostics {
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            listeners: Mutex::new(HashMap::new()),
            pending: Mutex::new(VecDeque::new()),
            next_listener_id: AtomicU64::new(1),
        })
    }

    pub fn dispatcher(self: &Arc<Self>) -> tracing::Dispatch {
        tracing::Dispatch::new(tracing_subscriber::registry().with(DiagnosticLayer {
            diagnostics: self.clone(),
        }))
    }

    pub fn subscribe(&self, listener: Arc<dyn CoreDiagnosticListener>) -> u64 {
        let id = self.next_listener_id.fetch_add(1, Ordering::Relaxed);
        if let Ok(mut listeners) = self.listeners.lock() {
            listeners.insert(id, listener);
        }
        id
    }

    pub fn unsubscribe(&self, id: u64) {
        if let Ok(mut listeners) = self.listeners.lock() {
            listeners.remove(&id);
        }
    }

    pub fn flush(&self) {
        let records = match self.pending.lock() {
            Ok(mut pending) => pending.drain(..).collect::<Vec<_>>(),
            Err(_) => return,
        };
        if records.is_empty() {
            return;
        }
        let listeners = match self.listeners.lock() {
            Ok(listeners) => listeners.values().cloned().collect::<Vec<_>>(),
            Err(_) => return,
        };
        for record in records {
            for listener in &listeners {
                listener.on_diagnostic(record.clone());
            }
        }
    }

    fn capture(&self, record: DiagnosticRecord) {
        if let Ok(mut pending) = self.pending.lock() {
            if pending.len() == MAX_PENDING_RECORDS {
                pending.pop_front();
            }
            pending.push_back(record);
        }
    }
}

struct DiagnosticLayer {
    diagnostics: Arc<Diagnostics>,
}

impl<S> Layer<S> for DiagnosticLayer
where
    S: Subscriber,
{
    fn on_event(&self, event: &Event<'_>, _context: tracing_subscriber::layer::Context<'_, S>) {
        let metadata = event.metadata();
        let mut visitor = MessageVisitor::default();
        event.record(&mut visitor);
        self.diagnostics.capture(DiagnosticRecord {
            level: match *metadata.level() {
                Level::TRACE => DiagnosticLevel::Trace,
                Level::DEBUG => DiagnosticLevel::Debug,
                Level::INFO => DiagnosticLevel::Info,
                Level::WARN => DiagnosticLevel::Warn,
                Level::ERROR => DiagnosticLevel::Error,
            },
            target: metadata.target().to_string(),
            message: visitor
                .message
                .unwrap_or_else(|| metadata.name().to_string()),
        });
    }
}

#[derive(Default)]
struct MessageVisitor {
    message: Option<String>,
}

impl Visit for MessageVisitor {
    fn record_debug(&mut self, field: &Field, value: &dyn std::fmt::Debug) {
        if field.name() == "message" {
            self.message = Some(format!("{value:?}"));
        }
    }

    fn record_str(&mut self, field: &Field, value: &str) {
        if field.name() == "message" {
            self.message = Some(value.to_string());
        }
    }
}
