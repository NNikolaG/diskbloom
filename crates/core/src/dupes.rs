//! Duplicate files: identical content in more than one place.
//!
//! Three steps, so that as little as possible is read from disk:
//! 1. group by size, from the scanned tree (no I/O),
//! 2. BLAKE3 hash of the first 64 KB, which rules out almost every size collision,
//! 3. full BLAKE3 hash, only for what is left.
//!
//! Hard links are not reported (the scanner counts them once, the others have size 0).
//! APFS clones look like duplicates, but deleting a clone frees nothing; that cannot be
//! detected reliably from user space.

use crate::tree::{NodeId, Tree};
use rayon::prelude::*;
use std::collections::HashMap;
use std::fs::File;
use std::hash::Hash;
use std::io::{self, Read};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

/// Bytes hashed in step 2.
const HEAD: u64 = 64 * 1024;

/// Files with the same content.
#[derive(Debug, Clone, PartialEq)]
pub struct DupGroup {
    /// Allocated size of one file.
    pub size: u64,
    /// At least two files, sorted by id.
    pub files: Vec<NodeId>,
}

impl DupGroup {
    /// Bytes freed by keeping only one copy.
    pub fn wasted(&self) -> u64 {
        self.size * (self.files.len() as u64).saturating_sub(1)
    }
}

type FileRef = (NodeId, PathBuf);

/// Searches a scanned tree for duplicates. Progress and cancellation can be used from
/// other threads while [`DupeFinder::find`] runs.
#[derive(Default)]
pub struct DupeFinder {
    cancelled: AtomicBool,
    total: AtomicU64,
    done: AtomicU64,
}

impl DupeFinder {
    /// A new finder.
    pub fn new() -> Self {
        Self::default()
    }

    /// Stops a running search.
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Relaxed);
    }

    /// Whether [`DupeFinder::cancel`] was called.
    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Relaxed)
    }

    /// `(files checked, files to check)`.
    pub fn progress(&self) -> (u64, u64) {
        (
            self.done.load(Ordering::Relaxed),
            self.total.load(Ordering::Relaxed),
        )
    }

    /// Finds duplicates among files of at least `min_size` bytes, most wasted space first.
    pub fn find(&self, tree: &Tree, min_size: u64) -> Vec<DupGroup> {
        let jobs: Vec<(u64, Vec<FileRef>)> = tree
            .same_size_groups(min_size.max(1))
            .into_iter()
            .map(|ids| {
                let size = tree.get(ids[0]).map_or(0, |e| e.size);
                (
                    size,
                    ids.into_iter().map(|id| (id, tree.path(id))).collect(),
                )
            })
            .collect();
        let total = jobs.iter().map(|(_, files)| files.len() as u64).sum();
        self.total.store(total, Ordering::Relaxed);

        let mut out: Vec<DupGroup> = jobs
            .into_par_iter()
            .flat_map_iter(|(size, files)| {
                let n = files.len() as u64;
                let found = if self.is_cancelled() {
                    Vec::new()
                } else {
                    self.check_group(size, files)
                };
                self.done.fetch_add(n, Ordering::Relaxed);
                found
            })
            .collect();
        out.sort_by_key(|g| std::cmp::Reverse(g.wasted()));
        out
    }

    fn check_group(&self, size: u64, files: Vec<FileRef>) -> Vec<DupGroup> {
        // Same allocated size does not mean same length, so compare the real length first.
        let by_len = split_by(files, |p| {
            let m = std::fs::symlink_metadata(p)?;
            if m.is_file() {
                Ok(m.len())
            } else {
                Err(io::ErrorKind::InvalidInput.into())
            }
        });
        let mut out = Vec::new();
        for (len, files) in by_len {
            for (_, files) in split_by(files, |p| hash_file(p, HEAD)) {
                // Files that fit in the head are already fully compared.
                let groups: Vec<Vec<FileRef>> = if len <= HEAD {
                    vec![files]
                } else {
                    split_by(files, |p| hash_file(p, u64::MAX))
                        .into_iter()
                        .map(|(_, same)| same)
                        .collect()
                };
                for same in groups {
                    if self.is_cancelled() {
                        return out;
                    }
                    let mut ids: Vec<NodeId> = same.into_iter().map(|(id, _)| id).collect();
                    ids.sort_unstable();
                    out.push(DupGroup { size, files: ids });
                }
            }
        }
        out
    }
}

/// Groups files by `key`, keeping only groups of two or more. Unreadable files are skipped.
fn split_by<K: Hash + Eq>(
    files: Vec<FileRef>,
    key: impl Fn(&Path) -> io::Result<K>,
) -> Vec<(K, Vec<FileRef>)> {
    let mut groups: HashMap<K, Vec<FileRef>> = HashMap::new();
    for (id, path) in files {
        if let Ok(k) = key(&path) {
            groups.entry(k).or_default().push((id, path));
        }
    }
    groups.into_iter().filter(|(_, v)| v.len() > 1).collect()
}

/// BLAKE3 of the first `limit` bytes.
fn hash_file(path: &Path, limit: u64) -> io::Result<[u8; 32]> {
    let mut hasher = blake3::Hasher::new();
    hasher.update_reader(File::open(path)?.take(limit))?;
    Ok(*hasher.finalize().as_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scan::Scanner;
    use std::fs;

    #[test]
    fn finds_true_duplicates_only() {
        let d = tempfile::tempdir().unwrap();
        let r = fs::canonicalize(d.path()).unwrap();
        let big: Vec<u8> = (0..200_000u32).map(|i| (i % 251) as u8).collect();
        let mut near = big.clone();
        *near.last_mut().unwrap() ^= 1; // same size and head, different tail
        fs::create_dir_all(r.join("a/b")).unwrap();
        fs::write(r.join("one.bin"), &big).unwrap();
        fs::write(r.join("a/two.bin"), &big).unwrap();
        fs::write(r.join("a/b/three.bin"), &big).unwrap();
        fs::write(r.join("near.bin"), &near).unwrap();
        fs::hard_link(r.join("one.bin"), r.join("hardlink.bin")).unwrap();
        fs::write(r.join("small1"), b"x").unwrap();
        fs::write(r.join("small2"), b"x").unwrap();

        let tree = Tree::from_node(Scanner::new(&r, false).unwrap().scan().unwrap(), r.clone());
        let finder = DupeFinder::new();
        let groups = finder.find(&tree, 10_000);
        assert_eq!(groups.len(), 1, "{groups:?}");
        let mut names: Vec<_> = groups[0]
            .files
            .iter()
            .map(|&id| {
                tree.path(id)
                    .strip_prefix(&r)
                    .unwrap()
                    .to_string_lossy()
                    .into_owned()
            })
            .collect();
        names.sort();
        // three real copies; the hard link is not counted twice and "near" differs
        assert_eq!(names.len(), 3);
        assert!(names.contains(&"a/two.bin".to_string()));
        assert!(names.contains(&"a/b/three.bin".to_string()));
        assert!(!names.iter().any(|n| n == "near.bin"));
        assert_eq!(groups[0].wasted(), groups[0].size * 2);
        let (done, total) = finder.progress();
        assert_eq!(done, total);
    }

    #[test]
    fn small_files_are_compared_by_head_hash() {
        let d = tempfile::tempdir().unwrap();
        let r = fs::canonicalize(d.path()).unwrap();
        fs::write(r.join("a"), vec![3u8; 20_000]).unwrap();
        fs::write(r.join("b"), vec![3u8; 20_000]).unwrap();
        fs::write(r.join("c"), vec![4u8; 20_000]).unwrap();
        let tree = Tree::from_node(Scanner::new(&r, false).unwrap().scan().unwrap(), r.clone());
        let groups = DupeFinder::new().find(&tree, 1);
        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].files.len(), 2);
    }
}
