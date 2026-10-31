//! Paralelni skener fajl sistema (sloj 2 iz MAP.md).

use rayon::prelude::*;
use std::collections::HashSet;
use std::fs::{self, Metadata};
use std::os::unix::fs::MetadataExt;
use std::path::Path;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

/// Cvor stabla (sloj 3). `size` je *alocirana* velicina (blokovi na disku).
#[derive(Debug, Clone)]
pub struct Node {
    pub name: String,
    pub size: u64,
    pub files: u64,
    pub is_dir: bool,
    pub children: Vec<Node>,
}

pub struct Scanner {
    root_dev: u64,
    cross_fs: bool,
    seen_inodes: Mutex<HashSet<(u64, u64)>>,
    pub errors: AtomicU64,
    pub scanned: AtomicU64,
    cancelled: AtomicBool,
}

/// Velicina na disku: st_blocks je uvek u jedinicama od 512 bajtova.
fn alloc_size(m: &Metadata) -> u64 {
    m.blocks() * 512
}

impl Scanner {
    pub fn new(root: &Path, cross_fs: bool) -> std::io::Result<Self> {
        let m = fs::symlink_metadata(root)?;
        Ok(Self {
            root_dev: m.dev(),
            cross_fs,
            seen_inodes: Mutex::new(HashSet::new()),
            errors: AtomicU64::new(0),
            scanned: AtomicU64::new(0),
            cancelled: AtomicBool::new(false),
        })
    }

    /// Prekida skeniranje u toku (bezbedno iz druge niti).
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Relaxed);
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Relaxed)
    }

    pub fn scan(&self, root: &Path) -> std::io::Result<Node> {
        let m = fs::symlink_metadata(root)?;
        let name = root.to_string_lossy().into_owned();
        Ok(self.visit(root, name, &m))
    }

    fn visit(&self, path: &Path, name: String, m: &Metadata) -> Node {
        self.scanned.fetch_add(1, Ordering::Relaxed);

        if !m.is_dir() {
            // Hardlink: isti (dev, ino) brojimo samo jednom.
            let mut size = alloc_size(m);
            if m.nlink() > 1 && !m.is_symlink() {
                let fresh = self.seen_inodes.lock().unwrap().insert((m.dev(), m.ino()));
                if !fresh {
                    size = 0;
                }
            }
            return Node {
                name,
                size,
                files: 1,
                is_dir: false,
                children: Vec::new(),
            };
        }

        let own = alloc_size(m);
        if self.is_cancelled() {
            return Node {
                name,
                size: own,
                files: 0,
                is_dir: true,
                children: Vec::new(),
            };
        }
        // Ne prelazimo u druge volumene (mount point-ovi).
        if !self.cross_fs && m.dev() != self.root_dev {
            return Node {
                name,
                size: own,
                files: 0,
                is_dir: true,
                children: Vec::new(),
            };
        }

        let entries: Vec<_> = match fs::read_dir(path) {
            Ok(rd) => rd
                .filter_map(|e| match e {
                    Ok(e) => Some(e),
                    Err(_) => {
                        self.errors.fetch_add(1, Ordering::Relaxed);
                        None
                    }
                })
                .collect(),
            Err(_) => {
                self.errors.fetch_add(1, Ordering::Relaxed);
                return Node {
                    name,
                    size: own,
                    files: 0,
                    is_dir: true,
                    children: Vec::new(),
                };
            }
        };

        // DirEntry::metadata ne prati symlinkove (lstat semantika).
        let mut children: Vec<Node> = entries
            .par_iter()
            .filter_map(|e| match e.metadata() {
                Ok(cm) => {
                    let cname = e.file_name().to_string_lossy().into_owned();
                    Some(self.visit(&e.path(), cname, &cm))
                }
                Err(_) => {
                    self.errors.fetch_add(1, Ordering::Relaxed);
                    None
                }
            })
            .collect();

        children.sort_unstable_by_key(|c| std::cmp::Reverse(c.size));
        let size = own + children.iter().map(|c| c.size).sum::<u64>();
        let files = children.iter().map(|c| c.files).sum();
        Node {
            name,
            size,
            files,
            is_dir: true,
            children,
        }
    }
}

pub fn human(bytes: u64) -> String {
    const U: [&str; 6] = ["B", "KB", "MB", "GB", "TB", "PB"];
    let mut v = bytes as f64;
    let mut i = 0;
    while v >= 1000.0 && i < U.len() - 1 {
        v /= 1000.0;
        i += 1;
    }
    if i == 0 {
        format!("{bytes} B")
    } else {
        format!("{v:.1} {}", U[i])
    }
}
