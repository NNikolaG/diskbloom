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
    /// Regenerise se samo (build, kes); inace korisnik treba da pogleda.
    pub safe: bool,
    pub is_dir: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FileInfo {
    pub id: u32,
    pub name: String,
    pub path: String,
    pub size: u64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct DupGroupInfo {
    /// Velicina jednog fajla.
    pub size: u64,
    /// Koliko bi se oslobodilo kad bi ostala jedna kopija.
    pub wasted: u64,
    pub files: Vec<FileInfo>,
}

const DATA_VOLUME: &str = "/System/Volumes/Data";

/// Kad se skenira boot disk, skener ide kroz `/System/Volumes/Data/...`. macOS takve
/// putanje (ispod zasticenog /System) ne pusta u korisnikov Trash ("You do not have
/// permission to move the files to the trash"), a isti fajl preko `/Users/...` pusta.
/// Zato aplikaciji vracamo uobicajenu putanju kroz firmlink, ako postoji.
fn user_path(p: &std::path::Path) -> String {
    user_path_with(p, DATA_VOLUME, |q| q.exists())
}

fn user_path_with(
    p: &std::path::Path,
    data: &str,
    exists: impl Fn(&std::path::Path) -> bool,
) -> String {
    if let Ok(rest) = p.strip_prefix(data)
        && !rest.as_os_str().is_empty()
    {
        let short = std::path::Path::new("/").join(rest);
        if exists(&short) {
            return short.to_string_lossy().into_owned();
        }
    }
    p.to_string_lossy().into_owned()
}

fn file_info(t: &dc::Tree, id: u32) -> Option<FileInfo> {
    t.get(id).map(|e| FileInfo {
        id,
        name: e.name.clone(),
        path: user_path(&t.path(id)),
        size: e.size,
    })
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

    /// Putanja za rad sa fajlom (Trash, Finder, Quick Look); vidi `user_path`.
    pub fn path(&self, id: u32) -> String {
        user_path(&self.inner.read().unwrap().path(id))
    }

    /// Nalazi cvor po putanji. Prihvata i putanje sa symlinkovima (/var -> /private/var)
    /// i obicne putanje kad je skeniran boot disk (/Users/x -> /System/Volumes/Data/Users/x).
    pub fn find(&self, path: String) -> Option<u32> {
        let t = self.inner.read().unwrap();
        let p = std::path::Path::new(&path);
        t.find(p)
            .or_else(|| std::fs::canonicalize(p).ok().and_then(|c| t.find(&c)))
            .or_else(|| {
                let data = std::path::Path::new(DATA_VOLUME);
                let rel = p.strip_prefix("/").ok()?;
                t.find(&data.join(rel))
            })
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
                path: user_path(&c.path),
                size: c.size,
                category: c.category.to_string(),
                safe: c.safe,
                is_dir: c.is_dir,
            })
            .collect()
    }

    /// Posle brisanja sa diska: izbaci cvor i azuriraj velicine, bez ponovnog skeniranja.
    pub fn remove(&self, id: u32) -> u64 {
        self.inner.write().unwrap().remove(id)
    }

    pub fn is_attached(&self, id: u32) -> bool {
        self.inner.read().unwrap().is_attached(id)
    }

    /// Ponovo skenira samo ovaj folder i ubacuje rezultat u stablo. Vraca novi ID.
    /// Blokira dok skenira (pozvati van main niti); stablo je zakljucano samo pri ubacivanju.
    pub fn rescan(&self, id: u32) -> Result<u32, BloomError> {
        let path = self.inner.read().unwrap().path(id);
        let scanner = dc::Scanner::new(&path, false)?;
        let node = scanner.scan(&path)?;
        Ok(self.inner.write().unwrap().replace_subtree(id, node))
    }

    /// Najveci fajlovi na celom disku/folderu.
    pub fn largest_files(&self, limit: u32, min_size: u64) -> Vec<FileInfo> {
        let t = self.inner.read().unwrap();
        t.largest_files(limit as usize, min_size)
            .into_iter()
            .filter_map(|id| file_info(&t, id))
            .collect()
    }
}

/// Trazenje duplikata nad vec skeniranim stablom. `run` blokira; `progress_*`/`cancel`
/// su bezbedni iz drugih niti.
#[derive(uniffi::Object)]
pub struct DupeJob {
    tree: Arc<DiskTree>,
    min_size: u64,
    finder: dc::dupes::DupeFinder,
}

#[uniffi::export]
impl DupeJob {
    #[uniffi::constructor]
    pub fn new(tree: Arc<DiskTree>, min_size: u64) -> Arc<Self> {
        Arc::new(Self {
            tree,
            min_size,
            finder: dc::dupes::DupeFinder::new(),
        })
    }

    pub fn run(&self) -> Result<Vec<DupGroupInfo>, BloomError> {
        // Kopija stabla da brisanje u UI-ju ne ceka na citanje diska.
        let snapshot = self.tree.inner.read().unwrap().clone();
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
                    .filter_map(|&id| file_info(&snapshot, id))
                    .collect(),
            })
            .collect())
    }

    pub fn progress_done(&self) -> u64 {
        self.finder.done.load(std::sync::atomic::Ordering::Relaxed)
    }

    pub fn progress_total(&self) -> u64 {
        self.finder.total.load(std::sync::atomic::Ordering::Relaxed)
    }

    pub fn cancel(&self) {
        self.finder.cancel();
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
    fn largest_dupes_rescan() {
        let d = tempfile::tempdir().unwrap();
        let r = d.path();
        let data = vec![9u8; 100_000];
        std::fs::create_dir_all(r.join("x")).unwrap();
        std::fs::write(r.join("a.bin"), &data).unwrap();
        std::fs::write(r.join("x/b.bin"), &data).unwrap();
        let tree = ScanJob::new(r.to_string_lossy().into_owned())
            .unwrap()
            .run()
            .unwrap();
        assert_eq!(tree.largest_files(10, 1).len(), 2);

        let groups = DupeJob::new(tree.clone(), 1000).run().unwrap();
        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].files.len(), 2);
        assert_eq!(groups[0].wasted, groups[0].size);

        // novi fajl u x/, pa osvezi samo x/
        std::fs::write(r.join("x/c.bin"), vec![1u8; 300_000]).unwrap();
        let before = tree.info(tree.root()).unwrap().size;
        let x = tree
            .find(r.join("x").to_string_lossy().into_owned())
            .unwrap();
        let new_x = tree.rescan(x).unwrap();
        assert!(tree.is_attached(new_x) && !tree.is_attached(x));
        assert!(tree.info(tree.root()).unwrap().size >= before + 300_000);
        assert_eq!(tree.children(new_x).len(), 2);
    }

    #[test]
    fn user_path_strips_data_volume_when_firmlinked() {
        let yes = |_: &std::path::Path| true;
        let no = |_: &std::path::Path| false;
        let d = "/System/Volumes/Data";
        let p = std::path::Path::new("/System/Volumes/Data/Users/n/projects/x/node_modules");
        assert_eq!(
            user_path_with(p, d, yes),
            "/Users/n/projects/x/node_modules"
        );
        // nema firmlink-a -> ostaje puna putanja
        assert_eq!(user_path_with(p, d, no), p.to_string_lossy());
        // sam koren volumena i druge putanje se ne diraju
        assert_eq!(user_path_with(std::path::Path::new(d), d, yes), d);
        assert_eq!(
            user_path_with(std::path::Path::new("/Volumes/USB/a"), d, yes),
            "/Volumes/USB/a"
        );
    }

    #[test]
    fn cancel_reports_cancelled() {
        let d = tempfile::tempdir().unwrap();
        let job = ScanJob::new(d.path().to_string_lossy().into_owned()).unwrap();
        job.cancel();
        assert!(matches!(job.run(), Err(BloomError::Cancelled)));
    }
}
