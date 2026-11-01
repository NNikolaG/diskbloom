use crate::{BloomError, DiskTree, DupGroupInfo, FileInfo};
use diskbloom_core::dupes::DupeFinder;
use std::sync::Arc;

/// A duplicate search over an already scanned tree.
#[derive(uniffi::Object)]
pub struct DupeJob {
    tree: Arc<DiskTree>,
    min_size: u64,
    finder: DupeFinder,
}

#[uniffi::export]
impl DupeJob {
    /// Prepares a search among files of at least `min_size` bytes.
    #[uniffi::constructor]
    pub fn new(tree: Arc<DiskTree>, min_size: u64) -> Arc<Self> {
        Arc::new(Self {
            tree,
            min_size,
            finder: DupeFinder::new(),
        })
    }

    /// Searches. Blocks; call off the main thread.
    ///
    /// # Errors
    /// [`BloomError::Cancelled`] after [`DupeJob::cancel`].
    pub fn run(&self) -> Result<Vec<DupGroupInfo>, BloomError> {
        // Work on a copy so the UI can keep removing items while files are hashed.
        let snapshot = self.tree.snapshot();
        let groups = self.finder.find(&snapshot, self.min_size);
        if self.finder.is_cancelled() {
            return Err(BloomError::Cancelled);
        }
        Ok(groups
            .into_iter()
            .map(|g| DupGroupInfo {
                size: g.size,
                wasted: g.wasted(),
                files: g
                    .files
                    .iter()
                    .filter_map(|&id| FileInfo::new(&snapshot, id))
                    .collect(),
            })
            .collect())
    }

    /// Files compared so far.
    pub fn progress_done(&self) -> u64 {
        self.finder.progress().0
    }

    /// Files to compare.
    pub fn progress_total(&self) -> u64 {
        self.finder.progress().1
    }

    /// Stops a running search.
    pub fn cancel(&self) {
        self.finder.cancel();
    }
}
