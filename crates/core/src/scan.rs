//! Parallel file system scanner.
//!
//! Each folder is opened once, read, and every entry is `fstatat`-ed relative to the
//! open folder, so the kernel resolves one name per entry instead of the whole path
//! (std's `DirEntry::metadata` does a full-path `lstat` on macOS). The folder is closed
//! before descending, so open file descriptors do not grow with depth. Work is spread
//! over the rayon pool. Sizes are *allocated* sizes (`st_blocks * 512`), which is what
//! deleting frees.

use rayon::prelude::*;
use rustix::fs::{AtFlags, Dir, FileType, Mode, OFlags, Stat};
use std::collections::HashSet;
use std::ffi::{CString, OsStr};
use std::fs;
use std::io;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock, PoisonError};

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

/// The parts of `stat` the scanner uses, independent of the platform's field types.
#[derive(Clone, Copy)]
struct Info {
    kind: FileType,
    /// Allocated bytes: `st_blocks` is always in 512-byte units, whatever the block size.
    size: u64,
    dev: u64,
    ino: u64,
    nlink: u64,
}

fn to_u64<T: TryInto<u64>>(value: T) -> u64 {
    value.try_into().unwrap_or(0)
}

impl From<&Stat> for Info {
    fn from(st: &Stat) -> Self {
        Self {
            kind: FileType::from_raw_mode(st.st_mode),
            size: to_u64(st.st_blocks) * 512,
            dev: to_u64(st.st_dev),
            ino: to_u64(st.st_ino),
            nlink: to_u64(st.st_nlink),
        }
    }
}

impl From<&fs::Metadata> for Info {
    fn from(m: &fs::Metadata) -> Self {
        Self {
            kind: FileType::from_raw_mode(m.mode() as _),
            size: m.blocks() * 512,
            dev: m.dev(),
            ino: m.ino(),
            nlink: m.nlink(),
        }
    }
}

/// The scan mostly waits for the disk, not the CPU, so it runs on its own pool with more
/// threads than cores: on a 3-core Mac, 8 to 24 threads scanned up to twice as fast as 3.
/// `DISKBLOOM_SCAN_THREADS` overrides the count (for benchmarks).
fn scan_pool() -> Option<&'static rayon::ThreadPool> {
    static POOL: OnceLock<Option<rayon::ThreadPool>> = OnceLock::new();
    POOL.get_or_init(|| {
        let cores = std::thread::available_parallelism().map_or(4, usize::from);
        let threads = std::env::var("DISKBLOOM_SCAN_THREADS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or((cores * 4).clamp(16, 32));
        rayon::ThreadPoolBuilder::new()
            .num_threads(threads)
            .thread_name(|i| format!("diskbloom-scan-{i}"))
            .build()
            .ok()
    })
    .as_ref()
}

/// Entries below this count are stat-ed on one thread; splitting them costs more than it saves.
const PARALLEL_STAT_MIN: usize = 64;

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
        let info = Info::from(&fs::symlink_metadata(&self.root)?);
        let name = self.root.to_string_lossy().into_owned();
        self.scanned.fetch_add(1, Ordering::Relaxed);
        if info.kind == FileType::Directory {
            let visit = || self.visit_dir(&self.root, name, info);
            Ok(match scan_pool() {
                Some(pool) => pool.install(visit),
                None => visit(),
            })
        } else {
            Ok(Node::file(name, self.counted_size(&info)))
        }
    }

    fn visit_dir(&self, path: &Path, name: String, info: Info) -> Node {
        let other_volume = !self.cross_fs && info.dev != self.root_dev;
        if self.is_cancelled() || other_volume {
            return Node::unread_dir(name, info.size);
        }
        let Ok(entries) = self.read_dir(path) else {
            self.count_error();
            return Node::unread_dir(name, info.size);
        };
        self.scanned
            .fetch_add(entries.len() as u64, Ordering::Relaxed);
        let children = entries
            .into_par_iter()
            .map(|(child, child_info)| {
                let child_name = String::from_utf8_lossy(child.as_bytes()).into_owned();
                if child_info.kind == FileType::Directory {
                    let child_path = path.join(OsStr::from_bytes(child.as_bytes()));
                    self.visit_dir(&child_path, child_name, child_info)
                } else {
                    Node::file(child_name, self.counted_size(&child_info))
                }
            })
            .collect();
        Node::dir(name, info.size, children)
    }

    /// Names and stat info of everything in `path` (not following symlinks). The folder
    /// is closed when this returns.
    fn read_dir(&self, path: &Path) -> io::Result<Vec<(CString, Info)>> {
        let flags = OFlags::RDONLY | OFlags::DIRECTORY | OFlags::NOFOLLOW | OFlags::CLOEXEC;
        let mut dir = Dir::new(rustix::fs::open(path, flags, Mode::empty())?)?;
        let mut names = Vec::new();
        for entry in dir.by_ref() {
            match entry {
                Ok(entry) => {
                    let name = entry.file_name();
                    if name != c"." && name != c".." {
                        names.push(name.to_owned());
                    }
                }
                Err(_) => self.count_error(),
            }
        }
        let fd = dir.fd()?;
        let stat = |name: CString| {
            let st = rustix::fs::statat(fd, name.as_c_str(), AtFlags::SYMLINK_NOFOLLOW);
            if let Ok(st) = st {
                Some((name, Info::from(&st)))
            } else {
                self.count_error();
                None
            }
        };
        Ok(if names.len() < PARALLEL_STAT_MIN {
            names.into_iter().filter_map(stat).collect()
        } else {
            names
                .into_par_iter()
                .with_min_len(PARALLEL_STAT_MIN / 2)
                .filter_map(stat)
                .collect()
        })
    }

    /// Hard links share their blocks, so only the first link seen is counted.
    fn counted_size(&self, info: &Info) -> u64 {
        if info.nlink > 1 && info.kind != FileType::Symlink {
            let first = self
                .seen_inodes
                .lock()
                .unwrap_or_else(PoisonError::into_inner)
                .insert((info.dev, info.ino));
            if !first {
                return 0;
            }
        }
        info.size
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
