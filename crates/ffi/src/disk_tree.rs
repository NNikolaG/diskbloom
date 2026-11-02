use crate::paths::user_path;
use crate::{BloomError, CleanCandidate, FileInfo, GrowthInfo, NodeInfo, SegmentInfo};
use crate::{FileKind, KindInfo, SearchHit};
use diskbloom_core::{NodeId, ScanInfo, Scanner, Tree, clean, volume};
use std::fs::File;
use std::io::{BufReader, BufWriter};
use std::path::Path;
use std::sync::{Arc, PoisonError, RwLock, RwLockReadGuard, RwLockWriteGuard};

/// A scanned tree, shared with Swift. Reads run in parallel; updates (remove, rescan)
/// lock it briefly.
#[derive(uniffi::Object)]
pub struct DiskTree {
    inner: RwLock<Tree>,
    /// Set when the tree was loaded from a saved scan.
    saved: ScanInfo,
}

impl DiskTree {
    pub(crate) fn new(tree: Tree, saved: ScanInfo) -> Self {
        Self {
            inner: RwLock::new(tree),
            saved,
        }
    }

    /// Like `Tree::find`, accepting symlinked and short boot-volume forms of the path.
    fn find_in(t: &Tree, p: &Path) -> Option<NodeId> {
        t.find(p)
            .or_else(|| std::fs::canonicalize(p).ok().and_then(|c| t.find(&c)))
            .or_else(|| t.find(&volume::on_data_volume(p)))
    }

    // A panic while holding the lock cannot leave the tree half-updated in a way that
    // matters more than crashing the app, so a poisoned lock is still used.
    fn read(&self) -> RwLockReadGuard<'_, Tree> {
        self.inner.read().unwrap_or_else(PoisonError::into_inner)
    }

    fn write(&self) -> RwLockWriteGuard<'_, Tree> {
        self.inner.write().unwrap_or_else(PoisonError::into_inner)
    }

    pub(crate) fn snapshot(&self) -> Tree {
        self.read().clone()
    }
}

#[uniffi::export]
impl DiskTree {
    /// Id of the root.
    pub fn root(&self) -> u32 {
        self.read().root()
    }

    /// The scanned path.
    pub fn root_path(&self) -> String {
        self.read().root_path().to_string_lossy().into_owned()
    }

    /// One entry.
    pub fn info(&self, id: u32) -> Option<NodeInfo> {
        NodeInfo::new(&self.read(), id)
    }

    /// Children of `id`, largest first.
    pub fn children(&self, id: u32) -> Vec<NodeInfo> {
        let t = self.read();
        t.children(id)
            .iter()
            .filter_map(|&c| NodeInfo::new(&t, c))
            .collect()
    }

    /// From the root down to `id`, for the breadcrumb.
    pub fn ancestors(&self, id: u32) -> Vec<NodeInfo> {
        let t = self.read();
        t.ancestors(id)
            .into_iter()
            .filter_map(|a| NodeInfo::new(&t, a))
            .collect()
    }

    /// Path for the Trash, Finder and Quick Look (firmlinked form).
    pub fn path(&self, id: u32) -> String {
        user_path(&self.read().path(id))
    }

    /// Finds an entry by path. Also accepts paths through symlinks (`/var` →
    /// `/private/var`) and the short form when the boot disk was scanned
    /// (`/Users/x` → `/System/Volumes/Data/Users/x`).
    #[allow(clippy::needless_pass_by_value)] // UniFFI passes owned strings
    pub fn find(&self, path: String) -> Option<u32> {
        Self::find_in(&self.read(), Path::new(&path))
    }

    /// The deepest entry that contains `path` (the entry itself if it exists). For
    /// mapping a changed path reported by the system to the folder to rescan.
    #[allow(clippy::needless_pass_by_value)] // UniFFI passes owned strings
    pub fn find_nearest(&self, path: String) -> Option<u32> {
        let t = self.read();
        Path::new(&path)
            .ancestors()
            .find_map(|p| Self::find_in(&t, p))
    }

    /// An independent copy, e.g. to compare against after updating this tree.
    pub fn copy(&self) -> Arc<DiskTree> {
        Arc::new(DiskTree::new(self.snapshot(), self.saved))
    }

    /// Writes the tree to `path` (atomically, through a temporary file next to it).
    ///
    /// # Errors
    /// Fails if the file cannot be written.
    #[allow(clippy::needless_pass_by_value)] // UniFFI passes owned strings
    pub fn save(&self, path: String, scanned_at: i64, event_id: u64) -> Result<(), BloomError> {
        let target = Path::new(&path);
        let tmp = target.with_extension("tmp");
        {
            let file = File::create(&tmp)?;
            let info = ScanInfo {
                scanned_at,
                event_id,
            };
            self.read().save(BufWriter::new(file), info)?;
        }
        std::fs::rename(&tmp, target)?;
        Ok(())
    }

    /// Loads a tree saved with [`DiskTree::save`].
    ///
    /// # Errors
    /// Fails if the file is missing or damaged.
    #[uniffi::constructor]
    pub fn load(path: String) -> Result<Arc<Self>, BloomError> {
        let (tree, info) = Tree::load(BufReader::new(File::open(path)?))?;
        Ok(Arc::new(DiskTree::new(tree, info)))
    }

    /// When the loaded scan was made (Unix seconds); 0 for a fresh scan.
    pub fn saved_at(&self) -> i64 {
        self.saved.scanned_at
    }

    /// The marker stored with the loaded scan (the `FSEvents` event id); 0 for a fresh scan.
    pub fn saved_event_id(&self) -> u64 {
        self.saved.event_id
    }

    /// The most specific places that changed by at least `min_delta` bytes since `old`.
    #[allow(clippy::needless_pass_by_value)] // UniFFI passes objects as Arc
    pub fn growth_since(&self, old: Arc<DiskTree>, min_delta: u64, limit: u32) -> Vec<GrowthInfo> {
        let old = old.snapshot();
        self.read()
            .growth(&old, min_delta, limit as usize)
            .iter()
            .map(GrowthInfo::from)
            .collect()
    }

    /// Sunburst segments around `focus`; see `Tree::layout`.
    pub fn layout(&self, focus: u32, rings: u32, min_fraction: f64) -> Vec<SegmentInfo> {
        let t = self.read();
        t.layout(focus, rings, min_fraction)
            .into_iter()
            .map(|s| SegmentInfo::new(&t, &s))
            .collect()
    }

    /// Smart Clean candidates, largest first.
    pub fn clean_candidates(&self) -> Vec<CleanCandidate> {
        clean::find(&self.read())
            .into_iter()
            .map(CleanCandidate::from)
            .collect()
    }

    /// Drops an entry after it was deleted from disk; returns the bytes freed.
    pub fn remove(&self, id: u32) -> u64 {
        self.write().remove(id)
    }

    /// Whether the entry is still in the tree.
    pub fn is_attached(&self, id: u32) -> bool {
        self.read().is_attached(id)
    }

    /// Rescans one folder and puts the result in the tree; returns the new id.
    /// Blocks while scanning (call off the main thread); the tree is only locked for
    /// the swap.
    ///
    /// # Errors
    /// Fails if the folder cannot be read.
    pub fn rescan(&self, id: u32) -> Result<u32, BloomError> {
        let path = self.read().path(id);
        let node = Scanner::new(path, false)?.scan()?;
        Ok(self.write().replace_subtree(id, node))
    }

    /// The `limit` largest files of at least `min_size` bytes.
    pub fn largest_files(&self, limit: u32, min_size: u64) -> Vec<FileInfo> {
        let t = self.read();
        t.largest_files(limit as usize, min_size)
            .into_iter()
            .filter_map(|id| FileInfo::new(&t, id))
            .collect()
    }

    /// Size and number of items per file kind, for every kind (also empty ones).
    pub fn file_kinds(&self) -> Vec<KindInfo> {
        self.read()
            .kind_totals()
            .into_iter()
            .map(KindInfo::from)
            .collect()
    }

    /// The `limit` largest items of `kind`, largest first (an `.app` bundle as a whole).
    pub fn largest_of_kind(&self, kind: FileKind, limit: u32) -> Vec<FileInfo> {
        let t = self.read();
        t.largest_of_kind(kind.into(), limit as usize)
            .into_iter()
            .filter_map(|id| FileInfo::new(&t, id))
            .collect()
    }

    /// Files and folders whose name contains `query` (ignoring case and diacritics),
    /// largest first, at most `limit`. Walks the whole tree: call off the main thread.
    #[allow(clippy::needless_pass_by_value)] // UniFFI passes owned strings
    pub fn search(&self, query: String, limit: u32) -> Vec<SearchHit> {
        let t = self.read();
        t.search(&query, limit as usize)
            .into_iter()
            .filter_map(|id| SearchHit::new(&t, id))
            .collect()
    }
}
