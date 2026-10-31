//! UniFFI most izmedju `diskbloom-core` i Swift aplikacije.
//!
//! Dizajn: Swift nikad ne dobija celo stablo (stotine hiljada cvorova),
//! vec samo ID-jeve i ono sto trenutno crta (`layout`, `children`).

use diskbloom_core as dc;
use std::path::PathBuf;
use std::sync::{Arc, RwLock};

uniffi::setup_scaffolding!();

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum BloomError {
    #[error("{msg}")]
    Io { msg: String },
    #[error("scan cancelled")]
    Cancelled,
}

impl From<std::io::Error> for BloomError {
    fn from(e: std::io::Error) -> Self {
        BloomError::Io { msg: e.to_string() }
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct NodeInfo {
    pub id: u32,
    pub name: String,
    pub size: u64,
    pub files: u64,
    pub is_dir: bool,
    pub has_children: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct SegmentInfo {
    /// `None` = zbirni "smaller objects" segment.
    pub id: Option<u32>,
    pub parent: u32,
    pub name: String,
    pub depth: u32,
    /// Uglovi kao razlomak kruga, 0.0..=1.0, pocinje na 12 sati, u smeru kazaljke.
    pub start: f64,
    pub end: f64,
    pub hue: f64,
    pub size: u64,
    pub is_dir: bool,
    pub has_children: bool,
    pub aggregated: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct CleanCandidate {
    pub id: u32,
    pub path: String,
    pub size: u64,
    pub category: String,
    pub is_dir: bool,
}

/// Jedno skeniranje. `run` blokira (pozvati van main niti);
/// `scanned`/`cancel` su bezbedni iz drugih niti dok `run` traje.
#[derive(uniffi::Object)]
pub struct ScanJob {
    root: PathBuf,
    scanner: dc::Scanner,
}

#[uniffi::export]
impl ScanJob {
    #[uniffi::constructor]
    pub fn new(path: String) -> Result<Arc<Self>, BloomError> {
        let root = std::fs::canonicalize(path)?;
        let scanner = dc::Scanner::new(&root, false)?;
        Ok(Arc::new(Self { root, scanner }))
    }

    pub fn run(&self) -> Result<Arc<DiskTree>, BloomError> {
        let node = self.scanner.scan(&self.root)?;
        if self.scanner.is_cancelled() {
            return Err(BloomError::Cancelled);
        }
        Ok(Arc::new(DiskTree {
            inner: RwLock::new(dc::Tree::from_node(node, self.root.clone())),
        }))
    }

    pub fn scanned(&self) -> u64 {
        self.scanner
            .scanned
            .load(std::sync::atomic::Ordering::Relaxed)
    }

    /// Broj foldera/fajlova kojima nije bilo moguce pristupiti (npr. bez Full Disk Access).
    pub fn errors(&self) -> u64 {
        self.scanner
            .errors
            .load(std::sync::atomic::Ordering::Relaxed)
    }

    pub fn cancel(&self) {
        self.scanner.cancel();
    }
}

#[derive(uniffi::Object)]
pub struct DiskTree {
    inner: RwLock<dc::Tree>,
}

fn info(t: &dc::Tree, id: u32) -> Option<NodeInfo> {
    t.get(id).map(|e| NodeInfo {
        id,
        name: e.name.clone(),
        size: e.size,
        files: e.files,
        is_dir: e.is_dir,
        has_children: !e.children.is_empty(),
    })
}

#[uniffi::export]
impl DiskTree {
    pub fn root(&self) -> u32 {
        self.inner.read().unwrap().root()
    }

    pub fn root_path(&self) -> String {
        self.inner
            .read()
            .unwrap()
            .root_path()
            .to_string_lossy()
            .into_owned()
    }

    pub fn info(&self, id: u32) -> Option<NodeInfo> {
        info(&self.inner.read().unwrap(), id)
    }

    pub fn children(&self, id: u32) -> Vec<NodeInfo> {
        let t = self.inner.read().unwrap();
        t.children(id).iter().filter_map(|&c| info(&t, c)).collect()
    }

    /// Od korena do `id`, za breadcrumb.
    pub fn ancestors(&self, id: u32) -> Vec<NodeInfo> {
        let t = self.inner.read().unwrap();
        t.ancestors(id)
            .into_iter()
            .filter_map(|a| info(&t, a))
            .collect()
    }

    pub fn path(&self, id: u32) -> String {
        self.inner
            .read()
            .unwrap()
            .path(id)
            .to_string_lossy()
            .into_owned()
    }

    pub fn find(&self, path: String) -> Option<u32> {
        self.inner.read().unwrap().find(std::path::Path::new(&path))
    }

    pub fn layout(&self, focus: u32, rings: u32, min_fraction: f64) -> Vec<SegmentInfo> {
        let t = self.inner.read().unwrap();
        t.layout(focus, rings, min_fraction)
            .into_iter()
            .map(|s| {
                let e = s.id.and_then(|id| t.get(id));
                SegmentInfo {
                    id: s.id,
                    parent: s.parent,
                    name: match e {
                        Some(e) => e.name.clone(),
                        None => format!("{} smaller objects", s.aggregated),
                    },
                    depth: s.depth,
                    start: s.start,
                    end: s.end,
                    hue: s.hue,
                    size: s.size,
                    is_dir: e.is_some_and(|e| e.is_dir),
                    has_children: e.is_some_and(|e| !e.children.is_empty()),
                    aggregated: s.aggregated,
                }
            })
            .collect()
    }

    pub fn clean_candidates(&self) -> Vec<CleanCandidate> {
        let t = self.inner.read().unwrap();
        dc::clean::find(&t)
            .into_iter()
            .map(|c| CleanCandidate {
                id: c.id,
                path: c.path.to_string_lossy().into_owned(),
                size: c.size,
                category: c.category.to_string(),
                is_dir: c.is_dir,
            })
            .collect()
    }

    /// Posle brisanja sa diska: izbaci cvor i azuriraj velicine, bez ponovnog skeniranja.
    pub fn remove(&self, id: u32) -> u64 {
        self.inner.write().unwrap().remove(id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scan_layout_clean_remove() {
        let d = tempfile::tempdir().unwrap();
        let r = d.path();
        std::fs::create_dir_all(r.join("p/target/debug")).unwrap();
        std::fs::write(r.join("p/Cargo.toml"), "x").unwrap();
        std::fs::write(r.join("p/target/debug/bin"), vec![1u8; 200_000]).unwrap();
        std::fs::write(r.join("big"), vec![1u8; 300_000]).unwrap();

        let job = ScanJob::new(r.to_string_lossy().into_owned()).unwrap();
        let tree = job.run().unwrap();
        assert!(job.scanned() >= 5);
        let root = tree.root();
        let before = tree.info(root).unwrap().size;

        let segs = tree.layout(root, 6, 0.0);
        assert!(segs.iter().any(|s| s.name == "big" && s.depth == 0));
        assert!(segs.iter().any(|s| s.name == "bin" && s.depth == 3));

        let c = tree.clean_candidates();
        assert_eq!(c.len(), 1);
        assert_eq!(c[0].category, "rust-build");
        assert_eq!(tree.find(c[0].path.clone()), Some(c[0].id));

        let freed = tree.remove(c[0].id);
        assert!(freed >= 200_000);
        assert_eq!(tree.info(root).unwrap().size, before - freed);
        assert!(tree.clean_candidates().is_empty());
    }

    #[test]
    fn cancel_reports_cancelled() {
        let d = tempfile::tempdir().unwrap();
        let job = ScanJob::new(d.path().to_string_lossy().into_owned()).unwrap();
        job.cancel();
        assert!(matches!(job.run(), Err(BloomError::Cancelled)));
    }
}
