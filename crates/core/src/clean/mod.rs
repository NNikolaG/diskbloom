//! Smart Clean: finds regenerable data, emulators, caches and similar.
//!
//! Two kinds of rules (see [`rules`]):
//! - **name rules** apply anywhere, with a condition on neighbours or contents:
//!   `target/` only next to a `Cargo.toml`, a virtualenv only if it has `pyvenv.cfg`;
//! - **home rules** match known locations under `$HOME`: an exact path, every child
//!   of a folder (each cache in `~/Library/Caches`, each simulator), or children with
//!   an extension (`.dmg` in Downloads, `.avd` emulators).
//!
//! Name rules are switched off below protected locations (installed tools, app
//! bundles, `~/Library`), and the search never descends into `node_modules`.

mod category;
mod rules;
#[cfg(test)]
mod tests;

pub use category::Category;

use crate::tree::{NodeId, Tree};
use crate::volume;
use rules::{HOME_RULES, HomeRule, Kind, NAME_RULES, PROTECTED_ABS, PROTECTED_HOME};
use std::collections::{HashMap, HashSet};
use std::io;
use std::path::{Path, PathBuf};

/// Something that could be removed.
#[derive(Debug, Clone)]
pub struct Candidate {
    /// Entry in the scanned tree.
    pub id: NodeId,
    /// Absolute path, in the form the scan produced.
    pub path: PathBuf,
    /// Allocated size in bytes.
    pub size: u64,
    /// What it is.
    pub category: Category,
    /// Whether it is a folder.
    pub is_dir: bool,
}

impl Candidate {
    /// Safe to remove without looking; see [`Category::is_safe`].
    pub fn is_safe(&self) -> bool {
        self.category.is_safe()
    }
}

/// Rules resolved to absolute paths for one `$HOME`.
struct Rules {
    exact: HashMap<PathBuf, Category>,
    children: HashMap<PathBuf, &'static HomeRule>,
    /// Roots below which name rules do not apply.
    protected: HashSet<PathBuf>,
}

impl Rules {
    /// Every path is registered in both forms (`/Users/x` and
    /// `/System/Volumes/Data/Users/x`), because a boot disk scan reports the latter.
    fn new(home: Option<&Path>) -> Self {
        let mut rules = Rules {
            exact: HashMap::new(),
            children: HashMap::new(),
            protected: PROTECTED_ABS
                .iter()
                .flat_map(|p| volume::both_forms(PathBuf::from(p)))
                .collect(),
        };
        let Some(home) = home else { return rules };
        for rule in HOME_RULES {
            for path in volume::both_forms(home.join(rule.path)) {
                match rule.kind {
                    Kind::Exact => {
                        rules.exact.insert(path, rule.category);
                    }
                    Kind::Children | Kind::ChildrenExt(_) => {
                        rules.children.insert(path, rule);
                    }
                }
            }
        }
        for p in PROTECTED_HOME {
            rules.protected.extend(volume::both_forms(home.join(p)));
        }
        rules
    }

    fn is_protected(&self, path: &Path) -> bool {
        // A boot disk scan starts at the data volume; look at it as "/".
        let path = volume::strip_data_volume(path).unwrap_or_else(|| path.to_path_buf());
        self.protected.iter().any(|p| path.starts_with(p))
    }
}

/// Finds cleanup candidates using `$HOME` from the environment. Largest first.
pub fn find(tree: &Tree) -> Vec<Candidate> {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    find_with_home(tree, home.as_deref())
}

/// Like [`find`], with an explicit home folder.
pub fn find_with_home(tree: &Tree, home: Option<&Path>) -> Vec<Candidate> {
    let rules = Rules::new(home);
    let mut walk = Walk {
        tree,
        rules: &rules,
        out: Vec::new(),
    };
    let root = tree.root();
    let root_path = tree.root_path();
    // A scan that starts inside a protected folder (say ~/.nvm) gets no name rules at all.
    let names = !rules.is_protected(root_path);
    // The root itself is never a candidate, only what is below it.
    for &c in tree.children(root) {
        if let Some(e) = tree.get(c) {
            walk.visit(c, root, root_path, &root_path.join(&e.name), names);
        }
    }
    walk.out.sort_by_key(|c| std::cmp::Reverse(c.size));
    walk.out
}

struct Walk<'a> {
    tree: &'a Tree,
    rules: &'a Rules,
    out: Vec<Candidate>,
}

impl Walk<'_> {
    /// `names`: whether name rules apply in this part of the tree.
    fn visit(&mut self, id: NodeId, parent: NodeId, parent_path: &Path, path: &Path, names: bool) {
        let Some(e) = self.tree.get(id) else { return };
        let names = names
            && !self.rules.protected.contains(path)
            // Electron apps ship a package.json and node_modules inside the bundle.
            && !(e.is_dir && is_app_bundle(&e.name));
        if let Some(category) = self.classify(id, parent, parent_path, path, names) {
            if e.size > 0 {
                self.out.push(Candidate {
                    id,
                    path: path.to_path_buf(),
                    size: e.size,
                    category,
                    is_dir: e.is_dir,
                });
            }
            return; // a candidate is removed as a whole
        }
        // Everything inside node_modules belongs to installed packages (each has its own
        // package.json and node_modules), never to the project. Without this, parts of
        // global packages would be offered.
        if e.is_dir && e.name == "node_modules" {
            return;
        }
        for &c in self.tree.children(id) {
            if let Some(child) = self.tree.get(c) {
                self.visit(c, id, path, &path.join(&child.name), names);
            }
        }
    }

    fn classify(
        &self,
        id: NodeId,
        parent: NodeId,
        parent_path: &Path,
        path: &Path,
        names: bool,
    ) -> Option<Category> {
        let e = self.tree.get(id)?;
        if let Some(&category) = self.rules.exact.get(path) {
            return Some(category);
        }
        if let Some(rule) = self.rules.children.get(parent_path) {
            let matches = match rule.kind {
                Kind::ChildrenExt(exts) => Path::new(&e.name)
                    .extension()
                    .and_then(|x| x.to_str())
                    .is_some_and(|x| exts.iter().any(|want| want.eq_ignore_ascii_case(x))),
                Kind::Children | Kind::Exact => true,
            };
            if matches {
                return Some(rule.category);
            }
        }
        if !e.is_dir || !names {
            return None;
        }
        NAME_RULES
            .iter()
            .find(|r| {
                r.name.is_none_or(|n| n == e.name)
                    && (r.sibling.is_empty() || self.has_file(parent, r.sibling))
                    && (r.child.is_empty() || self.has_file(id, r.child))
            })
            .map(|r| r.category)
    }

    /// Whether folder `dir` directly contains a file with one of `names`.
    fn has_file(&self, dir: NodeId, names: &[&str]) -> bool {
        self.tree.children(dir).iter().any(|&c| {
            self.tree
                .get(c)
                .is_some_and(|e| !e.is_dir && names.contains(&e.name.as_str()))
        })
    }
}

fn is_app_bundle(name: &str) -> bool {
    Path::new(name)
        .extension()
        .is_some_and(|x| x.eq_ignore_ascii_case("app"))
}

/// Permanently deletes a candidate (used by the CLI; the app moves to the Trash).
///
/// # Errors
/// Fails if the path cannot be read or removed.
pub fn delete(c: &Candidate) -> io::Result<()> {
    // Never delete through a symlink: lstat, and remove_dir_all does not follow links.
    let m = std::fs::symlink_metadata(&c.path)?;
    if m.is_dir() {
        std::fs::remove_dir_all(&c.path)
    } else {
        std::fs::remove_file(&c.path)
    }
}
