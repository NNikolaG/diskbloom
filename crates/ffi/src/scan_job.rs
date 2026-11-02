use crate::{BloomError, DiskTree, SegmentInfo};
use diskbloom_core::{ScanInfo, Scanner, Tree};
use std::sync::Arc;

/// One scan of a folder.
#[derive(uniffi::Object)]
pub struct ScanJob {
    scanner: Scanner,
}

#[uniffi::export]
impl ScanJob {
    /// Prepares a scan of `path`. Symlinks in the path are resolved.
    ///
    /// # Errors
    /// Fails if the folder cannot be read.
    #[uniffi::constructor]
    pub fn new(path: String) -> Result<Arc<Self>, BloomError> {
        let root = std::fs::canonicalize(path)?;
        Ok(Arc::new(Self {
            scanner: Scanner::new(root, false)?,
        }))
    }

    /// Scans. Blocks; call off the main thread.
    ///
    /// # Errors
    /// [`BloomError::Cancelled`] after [`ScanJob::cancel`], or an I/O error if the root
    /// cannot be read.
    pub fn run(&self) -> Result<Arc<DiskTree>, BloomError> {
        let node = self.scanner.scan()?;
        if self.scanner.is_cancelled() {
            return Err(BloomError::Cancelled);
        }
        let tree = Tree::from_node(node, self.scanner.root().to_path_buf());
        Ok(Arc::new(DiskTree::new(tree, ScanInfo::default())))
    }

    /// Sunburst of what is known so far (finished top-level folders), for drawing while
    /// the scan runs. Cheap: previews keep only a few levels per folder.
    pub fn preview(&self, rings: u32, min_fraction: f64) -> Vec<SegmentInfo> {
        let tree = Tree::from_node(self.scanner.partial(), self.scanner.root().to_path_buf());
        tree.layout(tree.root(), rings, min_fraction)
            .iter()
            .map(|s| SegmentInfo::new(&tree, s))
            .collect()
    }

    /// Entries visited so far.
    pub fn scanned(&self) -> u64 {
        self.scanner.scanned()
    }

    /// Entries that could not be read (usually missing Full Disk Access).
    pub fn errors(&self) -> u64 {
        self.scanner.errors()
    }

    /// Stops a running scan; [`ScanJob::run`] then returns [`BloomError::Cancelled`].
    pub fn cancel(&self) {
        self.scanner.cancel();
    }
}
