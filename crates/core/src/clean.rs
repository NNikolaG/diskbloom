//! Cleaner: pravila za regenerisivo smece, emulatore, keseve i slicno.
//!
//! Dve vrste pravila:
//! - **po imenu** (bilo gde na disku), uz uslov o susedima ili deci:
//!   `target/` samo pored `Cargo.toml`, virtualenv samo ako sadrzi `pyvenv.cfg`;
//! - **po putanji u $HOME**: tacna putanja, svako dete foldera (npr. svaki kes u
//!   `~/Library/Caches`, svaki simulator), ili deca sa odredjenom ekstenzijom
//!   (`.dmg` u Downloads, `.avd` emulatori).
//!
//! Svaka kategorija je `safe` (regenerise se sama: build, kes) ili nije
//! (emulatori, VM-ovi, backup-i, instaleri: korisnik treba da pogleda pre brisanja).

use crate::tree::{NodeId, Tree};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct Candidate {
    pub id: NodeId,
    pub path: PathBuf,
    pub size: u64,
    pub category: &'static str,
    /// Bezbedno za brisanje bez gledanja (regenerise se samo).
    pub safe: bool,
    pub is_dir: bool,
}

struct NameRule {
    /// `None` = bilo koje ime (pravilo se oslanja na `child`).
    name: Option<&'static str>,
    /// Bar jedan od ovih fajlova mora biti u istom folderu.
    sibling: &'static [&'static str],
    /// Bar jedan od ovih fajlova mora biti unutar foldera.
    child: &'static [&'static str],
    category: &'static str,
    safe: bool,
}

const fn name(
    n: &'static str,
    sibling: &'static [&'static str],
    category: &'static str,
) -> NameRule {
    NameRule {
        name: Some(n),
        sibling,
        child: &[],
        category,
        safe: true,
    }
}

const NAME_RULES: &[NameRule] = &[
    name("target", &["Cargo.toml"], "rust-build"),
    name("node_modules", &["package.json"], "node-deps"),
    name(".next", &["package.json"], "js-build"),
    name(".nuxt", &["package.json"], "js-build"),
    name(".turbo", &["package.json"], "js-build"),
    name("__pycache__", &[], "python-cache"),
    name(".pytest_cache", &[], "python-cache"),
    name(".mypy_cache", &[], "python-cache"),
    name(".ruff_cache", &[], "python-cache"),
    name(
        ".gradle",
        &[
            "build.gradle",
            "build.gradle.kts",
            "settings.gradle",
            "settings.gradle.kts",
        ],
        "gradle",
    ),
    name("build", &["build.gradle", "build.gradle.kts"], "gradle"),
    name("Pods", &["Podfile"], "cocoapods"),
    name(".build", &["Package.swift"], "swift-build"),
    name("DerivedData", &[], "xcode-derived"),
    // Python virtualenv: bilo koji folder sa pyvenv.cfg unutra
    NameRule {
        name: None,
        sibling: &[],
        child: &["pyvenv.cfg"],
        category: "python-venv",
        safe: false,
    },
];

enum Kind {
    /// Tacno ova putanja.
    Exact,
    /// Svako dete ovog foldera je zaseban kandidat.
    Children,
    /// Deca sa jednom od ovih ekstenzija (bez tacke, mala slova).
    ChildrenExt(&'static [&'static str]),
}

struct HomeRule {
    path: &'static str,
    kind: Kind,
    category: &'static str,
    safe: bool,
}

const fn home(path: &'static str, kind: Kind, category: &'static str, safe: bool) -> HomeRule {
    HomeRule {
        path,
        kind,
        category,
        safe,
    }
}

/// Putanje relativno na $HOME. Tacna pravila imaju prednost nad `Children`
/// (npr. `Library/Caches/Homebrew` je pkg-cache, ostala deca Caches su app-cache).
const HOME_RULES: &[HomeRule] = &[
    // --- Xcode i iOS simulatori
    home(
        "Library/Developer/Xcode/DerivedData",
        Kind::Exact,
        "xcode-derived",
        true,
    ),
    home(
        "Library/Developer/Xcode/iOS DeviceSupport",
        Kind::Children,
        "xcode-device-support",
        true,
    ),
    home(
        "Library/Developer/Xcode/watchOS DeviceSupport",
        Kind::Children,
        "xcode-device-support",
        true,
    ),
    home(
        "Library/Developer/Xcode/tvOS DeviceSupport",
        Kind::Children,
        "xcode-device-support",
        true,
    ),
    home(
        "Library/Developer/Xcode/visionOS DeviceSupport",
        Kind::Children,
        "xcode-device-support",
        true,
    ),
    home(
        "Library/Developer/Xcode/Archives",
        Kind::Children,
        "xcode-archives",
        false,
    ),
    home(
        "Library/Developer/CoreSimulator/Devices",
        Kind::Children,
        "simulators",
        false,
    ),
    home(
        "Library/Developer/CoreSimulator/Caches",
        Kind::Exact,
        "simulator-cache",
        true,
    ),
    home(
        "Library/Caches/com.apple.dt.Xcode",
        Kind::Exact,
        "xcode-derived",
        true,
    ),
    // --- Android
    home(
        ".android/avd",
        Kind::ChildrenExt(&["avd"]),
        "android-emulators",
        false,
    ),
    home(
        "Library/Android/sdk/system-images",
        Kind::Children,
        "android-images",
        false,
    ),
    home(".android/cache", Kind::Exact, "pkg-cache", true),
    // --- Virtuelne masine
    home(
        "Library/Containers/com.docker.docker/Data/vms",
        Kind::Exact,
        "vms",
        false,
    ),
    home(
        "Library/Containers/com.utmapp.UTM/Data/Documents",
        Kind::ChildrenExt(&["utm"]),
        "vms",
        false,
    ),
    home("Parallels", Kind::ChildrenExt(&["pvm"]), "vms", false),
    home(
        "Virtual Machines.localized",
        Kind::ChildrenExt(&["vmwarevm"]),
        "vms",
        false,
    ),
    // --- Kesevi paketnih menadzera
    home("Library/Caches/Homebrew", Kind::Exact, "pkg-cache", true),
    home("Library/Caches/pip", Kind::Exact, "pkg-cache", true),
    home("Library/Caches/Yarn", Kind::Exact, "pkg-cache", true),
    home("Library/Caches/CocoaPods", Kind::Exact, "pkg-cache", true),
    home("Library/Caches/pnpm", Kind::Exact, "pkg-cache", true),
    home("Library/pnpm/store", Kind::Exact, "pkg-cache", true),
    home(".npm/_cacache", Kind::Exact, "pkg-cache", true),
    home(".cargo/registry/cache", Kind::Exact, "pkg-cache", true),
    home(".gradle/caches", Kind::Exact, "pkg-cache", true),
    home(".gradle/wrapper/dists", Kind::Exact, "pkg-cache", true),
    home(".m2/repository", Kind::Exact, "pkg-cache", true),
    home("go/pkg/mod", Kind::Exact, "pkg-cache", true),
    home(".nuget/packages", Kind::Exact, "pkg-cache", true),
    home(".bun/install/cache", Kind::Exact, "pkg-cache", true),
    // --- Kesevi aplikacija i logovi
    home("Library/Caches", Kind::Children, "app-cache", true),
    home(".cache", Kind::Exact, "app-cache", true),
    home("Library/Logs", Kind::Exact, "logs", true),
    // --- Stvari koje treba pogledati
    home(
        "Library/Application Support/MobileSync/Backup",
        Kind::Children,
        "ios-backups",
        false,
    ),
    home(
        "Downloads",
        Kind::ChildrenExt(&["dmg", "pkg", "iso", "xip"]),
        "installers",
        false,
    ),
    home(".Trash", Kind::Exact, "trash", false),
    home(".local/share/Trash", Kind::Exact, "trash", false),
];

/// Sve kategorije, sa oznakom da li su bezbedne.
pub fn categories() -> Vec<(&'static str, bool)> {
    let mut v: Vec<_> = NAME_RULES
        .iter()
        .map(|r| (r.category, r.safe))
        .chain(HOME_RULES.iter().map(|r| (r.category, r.safe)))
        .collect();
    v.sort();
    v.dedup();
    v
}

struct Rules<'a> {
    exact: HashMap<PathBuf, &'a HomeRule>,
    children: HashMap<PathBuf, &'a HomeRule>,
}

impl<'a> Rules<'a> {
    fn new(home: Option<&Path>) -> Self {
        let mut exact = HashMap::new();
        let mut children = HashMap::new();
        if let Some(h) = home {
            for r in HOME_RULES {
                let p = h.join(r.path);
                match r.kind {
                    Kind::Exact => exact.insert(p, r),
                    Kind::Children | Kind::ChildrenExt(_) => children.insert(p, r),
                };
            }
        }
        Rules { exact, children }
    }
}

pub fn find(tree: &Tree) -> Vec<Candidate> {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    find_with_home(tree, home.as_deref())
}

pub fn find_with_home(tree: &Tree, home: Option<&Path>) -> Vec<Candidate> {
    let rules = Rules::new(home);
    let mut out = Vec::new();
    // Koren se nikad ne predlaze, samo njegovi potomci.
    let root = tree.root();
    let root_path = tree.root_path().to_path_buf();
    for &c in tree.children(root) {
        let p = root_path.join(&tree.get(c).unwrap().name);
        visit(tree, c, root, &root_path, &p, &rules, &mut out);
    }
    out.sort_by_key(|c| std::cmp::Reverse(c.size));
    out
}

fn visit(
    t: &Tree,
    id: NodeId,
    parent: NodeId,
    parent_path: &Path,
    path: &Path,
    rules: &Rules,
    out: &mut Vec<Candidate>,
) {
    let n = t.get(id).unwrap();
    if let Some((category, safe)) = classify(t, id, parent, parent_path, path, rules) {
        if n.size > 0 {
            out.push(Candidate {
                id,
                path: path.to_path_buf(),
                size: n.size,
                category,
                safe,
                is_dir: n.is_dir,
            });
        }
        return; // ne silazimo u ono sto je vec kandidat
    }
    for &c in t.children(id) {
        let cp = path.join(&t.get(c).unwrap().name);
        visit(t, c, id, path, &cp, rules, out);
    }
}

fn classify(
    t: &Tree,
    id: NodeId,
    parent: NodeId,
    parent_path: &Path,
    path: &Path,
    rules: &Rules,
) -> Option<(&'static str, bool)> {
    let n = t.get(id).unwrap();
    if let Some(r) = rules.exact.get(path) {
        return Some((r.category, r.safe));
    }
    if let Some(r) = rules.children.get(parent_path) {
        let ok = match r.kind {
            Kind::ChildrenExt(exts) => Path::new(&n.name)
                .extension()
                .and_then(|e| e.to_str())
                .is_some_and(|e| exts.iter().any(|x| x.eq_ignore_ascii_case(e))),
            _ => true,
        };
        if ok {
            return Some((r.category, r.safe));
        }
    }
    if !n.is_dir {
        return None;
    }
    let has_file = |dir: NodeId, names: &[&str]| {
        t.children(dir).iter().any(|&s| {
            let s = t.get(s).unwrap();
            !s.is_dir && names.contains(&s.name.as_str())
        })
    };
    NAME_RULES
        .iter()
        .find(|r| {
            r.name.is_none_or(|nm| nm == n.name)
                && (r.sibling.is_empty() || has_file(parent, r.sibling))
                && (r.child.is_empty() || has_file(id, r.child))
        })
        .map(|r| (r.category, r.safe))
}

/// Trajno brisanje (CLI). macOS aplikacija umesto ovoga salje u Trash.
pub fn delete(c: &Candidate) -> std::io::Result<()> {
    // Bezbednosna provera: nikad ne brisemo kroz symlink.
    let m = std::fs::symlink_metadata(&c.path)?;
    if m.is_dir() {
        std::fs::remove_dir_all(&c.path)
    } else {
        std::fs::remove_file(&c.path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scan::Scanner;
    use std::fs;

    #[test]
    fn rules_cover_projects_emulators_caches() {
        let d = tempfile::tempdir().unwrap();
        let r = fs::canonicalize(d.path()).unwrap();
        let w = |p: &str| {
            let p = r.join(p);
            fs::create_dir_all(p.parent().unwrap()).unwrap();
            fs::write(p, vec![7u8; 9000]).unwrap();
        };
        // projekti
        w("rs/Cargo.toml");
        w("rs/target/debug/app");
        w("notrust/target/keep");
        w("js/package.json");
        w("js/node_modules/x/i.js");
        w("py/__pycache__/m.pyc");
        w("py/.venv/pyvenv.cfg");
        w("py/.venv/lib/site/__pycache__/x.pyc"); // pokriven venv-om, ne posebno
        w("h/.DS_Store"); // vise se ne prijavljuje
        // home pravila
        w("h/Library/Caches/com.app.one/blob");
        w("h/Library/Caches/Homebrew/bottle.tar.gz");
        w("h/Library/Developer/CoreSimulator/Devices/AAAA-1111/data/x");
        w("h/Library/Developer/CoreSimulator/Devices/BBBB-2222/data/x");
        w("h/Library/Developer/Xcode/DerivedData/App-abc/Build/x");
        w("h/.android/avd/Pixel_8.avd/userdata.img");
        w("h/.android/avd/Pixel_8.ini");
        w("h/Downloads/Installer.dmg");
        w("h/Downloads/photo.jpg");

        let s = Scanner::new(&r, false).unwrap();
        let tree = Tree::from_node(s.scan(&r).unwrap(), r.clone());
        let c = find_with_home(&tree, Some(&r.join("h")));
        let mut got: Vec<_> = c
            .iter()
            .map(|c| {
                (
                    c.path
                        .strip_prefix(&r)
                        .unwrap()
                        .to_string_lossy()
                        .into_owned(),
                    c.category,
                    c.safe,
                )
            })
            .collect();
        got.sort();
        let want: Vec<(String, &str, bool)> = vec![
            (
                "h/.android/avd/Pixel_8.avd".into(),
                "android-emulators",
                false,
            ),
            ("h/Downloads/Installer.dmg".into(), "installers", false),
            ("h/Library/Caches/Homebrew".into(), "pkg-cache", true),
            ("h/Library/Caches/com.app.one".into(), "app-cache", true),
            (
                "h/Library/Developer/CoreSimulator/Devices/AAAA-1111".into(),
                "simulators",
                false,
            ),
            (
                "h/Library/Developer/CoreSimulator/Devices/BBBB-2222".into(),
                "simulators",
                false,
            ),
            (
                "h/Library/Developer/Xcode/DerivedData".into(),
                "xcode-derived",
                true,
            ),
            ("js/node_modules".into(), "node-deps", true),
            ("py/.venv".into(), "python-venv", false),
            ("py/__pycache__".into(), "python-cache", true),
            ("rs/target".into(), "rust-build", true),
        ];
        assert_eq!(got, want);
        for c in &c {
            assert_eq!(tree.find(&c.path), Some(c.id));
        }
    }

    #[test]
    fn scanning_inside_rule_folder_lists_children() {
        // Skeniranje samog ~/Library/Caches: svako dete je kandidat.
        let d = tempfile::tempdir().unwrap();
        let r = fs::canonicalize(d.path()).unwrap();
        let caches = r.join("Library/Caches");
        fs::create_dir_all(caches.join("a")).unwrap();
        fs::write(caches.join("a/f"), vec![1u8; 9000]).unwrap();
        let s = Scanner::new(&caches, false).unwrap();
        let tree = Tree::from_node(s.scan(&caches).unwrap(), caches.clone());
        let c = find_with_home(&tree, Some(&r));
        assert_eq!(c.len(), 1);
        assert_eq!(c[0].category, "app-cache");
    }
}
