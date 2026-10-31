//! Duplikati: isti sadrzaj na vise mesta.
//!
//! Tri koraka da bi se sto manje citalo sa diska:
//! 1. grupisanje po velicini (iz vec skeniranog stabla, bez I/O),
//! 2. BLAKE3 hes prvih 64 KB: odbacuje skoro sve "slucajno iste velicine",
//! 3. pun BLAKE3 hes samo za preostale kandidate.
//!
//! Hardlinkovi se ne prijavljuju (skener ih broji jednom, drugi ima velicinu 0).
//! APFS klonovi izgledaju kao duplikati, ali brisanje kopije ne oslobadja prostor;
//! to se iz korisnickog prostora ne moze pouzdano razlikovati.

use crate::tree::{NodeId, Tree};
use rayon::prelude::*;
use std::collections::HashMap;
use std::fs::File;
use std::io::{self, Read};
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

const HEAD: usize = 64 * 1024;

#[derive(Debug, Clone, PartialEq)]
pub struct DupGroup {
    /// Velicina jednog fajla (alocirana).
    pub size: u64,
    /// Fajlovi sa istim sadrzajem, najmanje dva.
    pub files: Vec<NodeId>,
}

impl DupGroup {
    /// Koliko bi se oslobodilo kad bi ostala samo jedna kopija.
    pub fn wasted(&self) -> u64 {
        self.size * (self.files.len() as u64 - 1)
    }
}

#[derive(Default)]
pub struct DupeFinder {
    cancelled: AtomicBool,
    /// Broj fajlova koje treba proveriti / koji su provereni.
    pub total: AtomicU64,
    pub done: AtomicU64,
}

impl DupeFinder {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Relaxed);
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Relaxed)
    }

    /// Trazi duplikate medju fajlovima od bar `min_size` bajtova.
    /// Rezultat je sortiran po izgubljenom prostoru, najvise prvo.
    pub fn find(&self, tree: &Tree, min_size: u64) -> Vec<DupGroup> {
        let groups = tree.same_size_groups(min_size.max(1));
        let jobs: Vec<(u64, Vec<(NodeId, std::path::PathBuf)>)> = groups
            .into_iter()
            .map(|ids| {
                let size = tree.get(ids[0]).map(|e| e.size).unwrap_or(0);
                (
                    size,
                    ids.into_iter().map(|id| (id, tree.path(id))).collect(),
                )
            })
            .collect();
        self.total.store(
            jobs.iter().map(|(_, v)| v.len() as u64).sum(),
            Ordering::Relaxed,
        );

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

    fn check_group(&self, size: u64, files: Vec<(NodeId, std::path::PathBuf)>) -> Vec<DupGroup> {
        // 1) prava (logicka) duzina: alocirana velicina je ista i za razlicite duzine
        let mut by_len: HashMap<u64, Vec<(NodeId, std::path::PathBuf)>> = HashMap::new();
        for (id, p) in files {
            if let Ok(m) = std::fs::symlink_metadata(&p)
                && m.is_file()
            {
                by_len.entry(m.len()).or_default().push((id, p));
            }
        }
        let mut out = Vec::new();
        for (_, files) in by_len.into_iter().filter(|(_, v)| v.len() > 1) {
            // 2) hes pocetka
            for (_, files) in split_by(files, |p| hash_file(p, Some(HEAD))) {
                // 3) pun hes (preskacemo ako je fajl ceo stao u "pocetak")
                for (_, same) in split_by(files, |p| hash_file(p, None)) {
                    if self.is_cancelled() {
                        return out;
                    }
                    let mut ids: Vec<NodeId> = same.into_iter().map(|(id, _)| id).collect();
                    ids.sort();
                    out.push(DupGroup { size, files: ids });
                }
            }
        }
        out
    }
}

/// Deli fajlove po kljucu; zadrzava samo grupe sa 2+ fajla. Fajlovi koji se ne mogu
/// procitati se preskacu.
fn split_by<K: std::hash::Hash + Eq>(
    files: Vec<(NodeId, std::path::PathBuf)>,
    key: impl Fn(&Path) -> io::Result<K>,
) -> Vec<(K, Vec<(NodeId, std::path::PathBuf)>)> {
    let mut m: HashMap<K, Vec<(NodeId, std::path::PathBuf)>> = HashMap::new();
    for (id, p) in files {
        if let Ok(k) = key(&p) {
            m.entry(k).or_default().push((id, p));
        }
    }
    m.into_iter().filter(|(_, v)| v.len() > 1).collect()
}

fn hash_file(path: &Path, limit: Option<usize>) -> io::Result<[u8; 32]> {
    let mut f = File::open(path)?;
    let mut h = blake3::Hasher::new();
    let mut buf = vec![0u8; 256 * 1024];
    let mut left = limit.unwrap_or(usize::MAX);
    while left > 0 {
        let want = buf.len().min(left);
        let n = f.read(&mut buf[..want])?;
        if n == 0 {
            break;
        }
        h.update(&buf[..n]);
        left -= n;
    }
    Ok(*h.finalize().as_bytes())
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
        let mut other = big.clone();
        *other.last_mut().unwrap() ^= 1; // ista velicina i pocetak, drugaciji kraj
        fs::create_dir_all(r.join("a/b")).unwrap();
        fs::write(r.join("one.bin"), &big).unwrap();
        fs::write(r.join("a/two.bin"), &big).unwrap();
        fs::write(r.join("a/b/three.bin"), &big).unwrap();
        fs::write(r.join("near.bin"), &other).unwrap();
        fs::hard_link(r.join("one.bin"), r.join("hardlink.bin")).unwrap();
        fs::write(r.join("small1"), b"x").unwrap();
        fs::write(r.join("small2"), b"x").unwrap();

        let s = Scanner::new(&r, false).unwrap();
        let tree = Tree::from_node(s.scan(&r).unwrap(), r.clone());
        let f = DupeFinder::new();
        let groups = f.find(&tree, 10_000);
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
        // tri prave kopije; hardlink se ne racuna dvaput, "near" nije duplikat
        assert_eq!(names.len(), 3);
        assert!(names.contains(&"a/two.bin".to_string()));
        assert!(names.contains(&"a/b/three.bin".to_string()));
        assert!(!names.iter().any(|n| n == "near.bin"));
        assert_eq!(groups[0].wasted(), groups[0].size * 2);
        assert_eq!(
            f.done.load(Ordering::Relaxed),
            f.total.load(Ordering::Relaxed)
        );
    }
}
