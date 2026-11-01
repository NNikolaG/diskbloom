//! Parallel file system scanner.
//!
//! One `read_dir` per folder and one `lstat` per entry, spread over the rayon pool.
//! Sizes are *allocated* sizes (`st_blocks * 512`), which is what deleting frees.

use rayon::prelude::*;
use std::collections::HashSet;
use std::fs::{self, DirEntry, Metadata};
use std::io;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Mutex, PoisonError};

/// A scanned file or folder, with its children sorted by size (largest first).
#[derive(Debug, Clone)]
pub struct Node {
    /// File name; for the scan root, the full path that was scanned.
    pub name: String,
    /// Allocated size in bytes, including all descendants.
    pub size: u64,
    /// Number of files below this node (1 for a file).
    pub files: u64,
    /// Whether this is a folder.
    pub is_dir: bool,
    /// Children, largest first. Empty for files and unreadable folders.
    pub children: Vec<Node>,
}

impl Node {
    fn file(name: String, size: u64) -> Self {
        Self {
            name,
            size,
            files: 1,
            is_dir: false,
            children: Vec::new(),
        }
    }

    /// A folder whose contents were not read (cancelled, other volume, no permission).
    fn unread_dir(name: String, own_size: u64) -> Self {
        Self {
            name,
            size: own_size,
            files: 0,
            is_dir: true,
            children: Vec::new(),
        }
    }

    fn dir(name: String, own_size: u64, mut children: Vec<Node>) -> Self {
        children.sort_unstable_by_key(|c| std::cmp::Reverse(c.size));
        Self {
            name,
            size: own_size + children.iter().map(|c| c.size).sum::<u64>(),
            files: children.iter().map(|c| c.files).sum(),
            is_dir: true,
            children,
        }
    }
}

/// Scans one folder tree. Progress and cancellation can be used from other threads
/// while [`Scanner::scan`] runs.
pub struct Scanner {
    root: PathBuf,
    root_dev: u64,
    cross_fs: bool,
    seen_inodes: Mutex<HashSet<(u64, u64)>>,
    errors: AtomicU64,
    scanned: AtomicU64,
    cancelled: AtomicBool,
}

/// Size on disk. `st_blocks` is always in 512-byte units, whatever the block size.
fn alloc_size(m: &Metadata) -> u64 {
    m.blocks() * 512
}

impl Scanner {
    /// Prepares a scan of `root`. With `cross_fs = false` the scan stays on the volume
    /// that holds `root` and does not enter other mount points.
    ///
    /// # Errors
    /// Fails if `root` cannot be read.
    pub fn new(root: impl Into<PathBuf>, cross_fs: bool) -> io::Result<Self> {
        let root = root.into();
        let m = fs::symlink_metadata(&root)?;
        Ok(Self {
            root,
            root_dev: m.dev(),
            cross_fs,
            seen_inodes: Mutex::new(HashSet::new()),
            errors: AtomicU64::new(0),
            scanned: AtomicU64::new(0),
            cancelled: AtomicBool::new(false),
        })
    }

    /// The folder this scanner reads.
    pub fn root(&self) -> &Path {
        &self.root
    }

    /// Stops a running scan. The result then contains what was read so far.
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Relaxed);
    }

    /// Whether [`Scanner::cancel`] was called.
    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Relaxed)
    }

    /// Entries visited so far.
    pub fn scanned(&self) -> u64 {
        self.scanned.load(Ordering::Relaxed)
    }

    /// Entries that could not be read, usually for lack of permission.
    pub fn errors(&self) -> u64 {
        self.errors.load(Ordering::Relaxed)
    }

    /// Scans the whole tree. Blocks until done or cancelled.
    ///
    /// # Errors
    /// Fails only if the root itself cannot be read; unreadable entries below it are
    /// counted in [`Scanner::errors`] and skipped.
    pub fn scan(&self) -> io::Result<Node> {
        let m = fs::symlink_metadata(&self.root)?;
        let name = self.root.to_string_lossy().into_owned();
        Ok(self.visit(&self.root, name, &m))
    }

    fn visit(&self, path: &Path, name: String, m: &Metadata) -> Node {
        self.scanned.fetch_add(1, Ordering::Relaxed);

        if !m.is_dir() {
            return Node::file(name, self.counted_size(m));
        }
        let own = alloc_size(m);
        let other_volume = !self.cross_fs && m.dev() != self.root_dev;
        if self.is_cancelled() || other_volume {
            return Node::unread_dir(name, own);
        }
        let Ok(read_dir) = fs::read_dir(path) else {
            self.count_error();
            return Node::unread_dir(name, own);
        };
        let entries: Vec<DirEntry> = read_dir
            .filter_map(|e| e.inspect_err(|_| self.count_error()).ok())
            .collect();

        // DirEntry::metadata does not follow symlinks (lstat semantics).
        let children = entries
            .par_iter()
            .filter_map(|e| {
                let cm = e.metadata().inspect_err(|_| self.count_error()).ok()?;
                let child_name = e.file_name().to_string_lossy().into_owned();
                Some(self.visit(&e.path(), child_name, &cm))
            })
            .collect();
        Node::dir(name, own, children)
    }

    /// Hard links share their blocks, so only the first link seen is counted.
    fn counted_size(&self, m: &Metadata) -> u64 {
        if m.nlink() > 1 && !m.is_symlink() {
            let first = self
                .seen_inodes
                .lock()
                .unwrap_or_else(PoisonError::into_inner)
                .insert((m.dev(), m.ino()));
            if !first {
                return 0;
            }
        }
        alloc_size(m)
    }

    fn count_error(&self) {
        self.errors.fetch_add(1, Ordering::Relaxed);
    }
}

/// Human-readable size with decimal units, like Finder: `1.5 GB`.
pub fn human(bytes: u64) -> String {
    const UNITS: [&str; 6] = ["B", "KB", "MB", "GB", "TB", "PB"];
    let mut value = bytes as f64;
    let mut unit = 0;
    while value >= 1000.0 && unit < UNITS.len() - 1 {
        value /= 1000.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{bytes} B")
    } else {
        format!("{value:.1} {}", UNITS[unit])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn human_uses_decimal_units() {
        assert_eq!(human(999), "999 B");
        assert_eq!(human(1_500), "1.5 KB");
        assert_eq!(human(2_000_000_000), "2.0 GB");
    }

    #[test]
    fn scan_counts_hard_links_once_and_sorts_children() {
        let d = tempfile::tempdir().unwrap();
        let r = d.path();
        fs::write(r.join("small"), vec![1u8; 10_000]).unwrap();
        fs::write(r.join("big"), vec![1u8; 100_000]).unwrap();
        fs::hard_link(r.join("big"), r.join("big-link")).unwrap();

        let node = Scanner::new(r, false).unwrap().scan().unwrap();
        let sizes: Vec<_> = node.children.iter().map(|c| c.size).collect();
        assert!(sizes.windows(2).all(|w| w[0] >= w[1]), "{sizes:?}");
        assert_eq!(sizes.iter().filter(|&&s| s == 0).count(), 1);
        assert_eq!(node.files, 3);
    }

    #[test]
    fn cancelled_scan_returns_partial_tree() {
        let d = tempfile::tempdir().unwrap();
        fs::create_dir(d.path().join("sub")).unwrap();
        let scanner = Scanner::new(d.path(), false).unwrap();
        scanner.cancel();
        let node = scanner.scan().unwrap();
        assert!(node.children.is_empty());
    }
}
