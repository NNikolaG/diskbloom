//! Cleaner (slojevi 5-6): pravila za regenerisivo smece + "collector" + brisanje.

use crate::tree::{NodeId, Tree};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct Candidate {
    pub id: NodeId,
    pub path: PathBuf,
    pub size: u64,
    pub category: &'static str,
    pub is_dir: bool,
}

/// Pravilo po imenu, sa opcionim uslovom da u istom folderu postoji neki od `sibling` fajlova.
struct NameRule {
    name: &'static str,
    sibling: &'static [&'static str],
    category: &'static str,
    dir: bool,
}

const NAME_RULES: &[NameRule] = &[
    NameRule {
        name: "target",
        sibling: &["Cargo.toml"],
        category: "rust-build",
        dir: true,
    },
    NameRule {
        name: "node_modules",
        sibling: &["package.json"],
        category: "node-deps",
        dir: true,
    },
    NameRule {
        name: ".next",
        sibling: &["package.json"],
        category: "js-build",
        dir: true,
    },
    NameRule {
        name: ".nuxt",
        sibling: &["package.json"],
        category: "js-build",
        dir: true,
    },
    NameRule {
        name: "__pycache__",
        sibling: &[],
        category: "python-cache",
        dir: true,
    },
    NameRule {
        name: ".pytest_cache",
        sibling: &[],
        category: "python-cache",
        dir: true,
    },
    NameRule {
        name: ".mypy_cache",
        sibling: &[],
        category: "python-cache",
        dir: true,
    },
    NameRule {
        name: ".ruff_cache",
        sibling: &[],
        category: "python-cache",
        dir: true,
    },
    NameRule {
        name: ".gradle",
        sibling: &[
            "build.gradle",
            "build.gradle.kts",
            "settings.gradle",
            "settings.gradle.kts",
        ],
        category: "gradle",
        dir: true,
    },
    NameRule {
        name: "build",
        sibling: &["build.gradle", "build.gradle.kts"],
        category: "gradle",
        dir: true,
    },
    NameRule {
        name: ".DS_Store",
        sibling: &[],
        category: "macos-junk",
        dir: false,
    },
];

/// Apsolutne putanje relativno na $HOME.
const HOME_RULES: &[(&str, &str)] = &[
    (".cache", "user-cache"),
    ("Library/Caches", "user-cache"),
    (".npm/_cacache", "pkg-cache"),
    (".cargo/registry/cache", "pkg-cache"),
    (".gradle/caches", "pkg-cache"),
    ("Library/Developer/Xcode/DerivedData", "xcode"),
    (".local/share/Trash", "trash"),
    (".Trash", "trash"),
];

pub fn find(tree: &Tree) -> Vec<Candidate> {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    find_with_home(tree, home.as_deref())
}

pub fn find_with_home(tree: &Tree, home: Option<&Path>) -> Vec<Candidate> {
    let home_rules: Vec<(PathBuf, &'static str)> = match home {
        Some(h) => HOME_RULES.iter().map(|(p, c)| (h.join(p), *c)).collect(),
        None => Vec::new(),
    };
    let mut out = Vec::new();
    // Koren se nikad ne predlaze za brisanje, samo njegovi potomci.
    let root = tree.root();
    for &c in tree.children(root) {
        visit(
            tree,
            c,
            root,
            &tree.root_path().join(&tree.get(c).unwrap().name),
            &home_rules,
            &mut out,
        );
    }
    out.sort_by_key(|c| std::cmp::Reverse(c.size));
    out
}

fn visit(
    t: &Tree,
    id: NodeId,
    parent: NodeId,
    path: &Path,
    home_rules: &[(PathBuf, &'static str)],
    out: &mut Vec<Candidate>,
) {
    let n = t.get(id).unwrap();
    if let Some(cat) = classify(t, id, parent, path, home_rules) {
        if n.size > 0 {
            out.push(Candidate {
                id,
                path: path.to_path_buf(),
                size: n.size,
                category: cat,
                is_dir: n.is_dir,
            });
        }
        return; // ne silazimo u ono sto je vec kandidat
    }
    for &c in t.children(id) {
        visit(
            t,
            c,
            id,
            &path.join(&t.get(c).unwrap().name),
            home_rules,
            out,
        );
    }
}

fn classify(
    t: &Tree,
    id: NodeId,
    parent: NodeId,
    path: &Path,
    home_rules: &[(PathBuf, &'static str)],
) -> Option<&'static str> {
    let n = t.get(id).unwrap();
    if n.is_dir
        && let Some((_, cat)) = home_rules.iter().find(|(p, _)| p == path)
    {
        return Some(cat);
    }
    NAME_RULES
        .iter()
        .find(|r| {
            r.name == n.name
                && r.dir == n.is_dir
                && (r.sibling.is_empty()
                    || t.children(parent).iter().any(|&s| {
                        let s = t.get(s).unwrap();
                        !s.is_dir && r.sibling.contains(&s.name.as_str())
                    }))
        })
        .map(|r| r.category)
}

/// Sve kategorije koje cleaner poznaje.
pub fn categories() -> Vec<&'static str> {
    let mut v: Vec<_> = NAME_RULES
        .iter()
        .map(|r| r.category)
        .chain(HOME_RULES.iter().map(|r| r.1))
        .collect();
    v.sort();
    v.dedup();
    v
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
    fn rules_respect_siblings_and_home() {
        let d = tempfile::tempdir().unwrap();
        let r = fs::canonicalize(d.path()).unwrap();
        let w = |p: &str, n: usize| {
            let p = r.join(p);
            fs::create_dir_all(p.parent().unwrap()).unwrap();
            fs::write(p, vec![7u8; n]).unwrap();
        };
        w("rs/Cargo.toml", 10);
        w("rs/target/debug/app", 9000);
        w("notrust/target/keep", 9000);
        w("js/package.json", 10);
        w("js/node_modules/x/i.js", 9000);
        w("py/__pycache__/m.pyc", 9000);
        w("home/.cache/thing", 9000);
        w("home/.DS_Store", 9000);

        let s = Scanner::new(&r, false).unwrap();
        let tree = Tree::from_node(s.scan(&r).unwrap(), r.clone());
        let c = find_with_home(&tree, Some(&r.join("home")));
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
                )
            })
            .collect();
        got.sort();
        assert_eq!(
            got,
            vec![
                ("home/.DS_Store".into(), "macos-junk"),
                ("home/.cache".into(), "user-cache"),
                ("js/node_modules".into(), "node-deps"),
                ("py/__pycache__".into(), "python-cache"),
                ("rs/target".into(), "rust-build"),
            ]
        );
        for c in &c {
            assert_eq!(tree.find(&c.path), Some(c.id));
        }
    }
}
