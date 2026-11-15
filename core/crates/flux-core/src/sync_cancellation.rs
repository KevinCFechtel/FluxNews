//! Run-scoped cooperative Sync cancellation primitives.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::domain::SyncCompleted;

/// Monotonic cancellation signal shared by one Sync run and its caller.
///
/// Once cancelled, a signal remains cancelled for its lifetime. A fresh Sync run must receive a
/// fresh signal so cancellation cannot leak into a later generation.
#[derive(Clone, Debug, Default)]
pub struct SyncCancellation {
    cancelled: Arc<AtomicBool>,
}

impl SyncCancellation {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Acquire)
    }
}

/// Internal cooperative result used between Sync phases.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum Cancellable<T> {
    Completed(T),
    Cancelled,
}

/// Normal terminal outcomes for a cooperatively cancellable Sync run.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SyncOutcome {
    Completed(SyncCompleted),
    Cancelled,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cancellation_is_monotonic_and_shared_across_clones() {
        let cancellation = SyncCancellation::new();
        let observer = cancellation.clone();

        assert!(!observer.is_cancelled());
        cancellation.cancel();
        assert!(observer.is_cancelled());
        observer.cancel();
        assert!(cancellation.is_cancelled());
    }
}
