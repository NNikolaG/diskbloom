//! What changed between two scans of the same folder: "Library grew by 12 GB".

use super::{NodeId, Tree};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// A folder or file whose size changed between two scans.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Change {
    /// Path in the newer scan (or the older one, for something that was removed).
    pub path: PathBuf,
    /// Entry in the newer tree; `None` if it no longer exists.
    pub id: Option<NodeId>,
    /// Size in the older scan (0 if it is new).
    pub old_size: u64,
    /// Size in the newer scan (0 if it was removed).
    pub new_size: u64,
}

impl Change {
    /// Growth in bytes; negative when it shrank.
    pub fn delta(&self) -> i128 {
        i128::from(self.new_size) - i128::from(self.old_size)
    }
}

struct Pass<'a> {
    new: &'a Tree,
    old: &'a Tree,
    min_delta: i128,
    out: Vec<Change>,
}

impl Tree {
    /// The most specific places that grew or shrank by at least `min_delta` bytes since
    /// `old`, largest change first, at most `limit`. A folder is broken down into its
    /// children when they explain at least half of its change; otherwise it is reported
    /// as a whole.
    pub fn growth(&self, old: &Tree, min_delta: u64, limit: usize) -> Vec<Change> {
        let mut pass = Pass {
            new: self,
            old,
            min_delta: i128::from(min_delta.max(1)),
            out: Vec::new(),
        };
        pass.compare(Some(self.root()), Some(old.root()), self.root_path());
        let mut out = pass.out;
        out.sort_by_key(|c| std::cmp::Reverse(c.delta().abs()));
        out.truncate(limit);
        out
    }
}

impl Pass<'_> {
    fn compare(&mut self, new: Option<NodeId>, old: Option<NodeId>, path: &Path) {
        let new_entry = new.and_then(|id| self.new.get(id));
        let old_entry = old.and_then(|id| self.old.get(id));
        let new_size = new_entry.map_or(0, |e| e.size);
        let old_size = old_entry.map_or(0, |e| e.size);
        let delta = i128::from(new_size) - i128::from(old_size);
        if delta.abs() < self.min_delta {
            return;
        }
        let report = |pass: &mut Self| {
            pass.out.push(Change {
                path: path.to_path_buf(),
                id: new,
                old_size,
                new_size,
            });
        };
        let (Some(new_id), Some(old_id)) = (new, old) else {
            return report(self); // appeared or disappeared as a whole
        };
        if !new_entry.is_some_and(|e| e.is_dir) || !old_entry.is_some_and(|e| e.is_dir) {
            return report(self);
        }

        let mut old_children: HashMap<&str, NodeId> = self
            .old
            .children(old_id)
            .iter()
            .filter_map(|&c| Some((self.old.get(c)?.name.as_str(), c)))
            .collect();
        let mut pairs: Vec<(String, Option<NodeId>, Option<NodeId>, i128)> = Vec::new();
        for &c in self.new.children(new_id) {
            let Some(e) = self.new.get(c) else { continue };
            let o = old_children.remove(e.name.as_str());
            let old_size = o.and_then(|o| self.old.get(o)).map_or(0, |e| e.size);
            pairs.push((
                e.name.clone(),
                Some(c),
                o,
                i128::from(e.size) - i128::from(old_size),
            ));
        }
        for (name, o) in old_children {
            let old_size = self.old.get(o).map_or(0, |e| e.size);
            pairs.push((name.to_owned(), None, Some(o), -i128::from(old_size)));
        }
        let significant: Vec<_> = pairs
            .into_iter()
            .filter(|p| p.3.abs() >= self.min_delta && p.3.signum() == delta.signum())
            .collect();
        let explained: i128 = significant.iter().map(|p| p.3).sum();
        if explained.abs() * 2 < delta.abs() {
            return report(self);
        }
        for (name, n, o, _) in significant {
            self.compare(n, o, &path.join(name));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tree::tests::{dir, leaf};

    fn tree(root: crate::Node) -> Tree {
        Tree::from_node(root, PathBuf::from("/r"))
    }

    fn summary(changes: &[Change]) -> Vec<(String, i128)> {
        changes
            .iter()
            .map(|c| (c.path.display().to_string(), c.delta()))
            .collect()
    }

    #[test]
    fn growth_points_at_the_folder_that_grew() {
        let old = tree(dir(
            "/r",
            vec![
                dir(
                    "lib",
                    vec![dir("caches", vec![leaf("a", 100)]), leaf("x", 50)],
                ),
                leaf("doc", 10),
            ],
        ));
        let new = tree(dir(
            "/r",
            vec![
                dir(
                    "lib",
                    vec![
                        dir("caches", vec![leaf("a", 100), leaf("b", 900)]),
                        leaf("x", 50),
                    ],
                ),
                leaf("doc", 10),
            ],
        ));
        assert_eq!(
            summary(&new.growth(&old, 100, 10)),
            vec![("/r/lib/caches/b".into(), 900)]
        );
    }

    #[test]
    fn spread_out_growth_is_reported_at_the_parent() {
        let old = tree(dir(
            "/r",
            vec![dir("p", vec![leaf("a", 10), leaf("b", 10)])],
        ));
        let new = tree(dir(
            "/r",
            vec![dir("p", vec![leaf("a", 60), leaf("b", 60)])],
        ));
        // neither child alone reaches 100, the folder does
        assert_eq!(
            summary(&new.growth(&old, 100, 10)),
            vec![("/r/p".into(), 100)]
        );
    }

    #[test]
    fn removed_and_new_entries_are_reported() {
        let old = tree(dir("/r", vec![leaf("gone", 500), leaf("keep", 5)]));
        let new = tree(dir("/r", vec![leaf("fresh", 300), leaf("keep", 5)]));
        let changes = new.growth(&old, 100, 10);
        assert_eq!(summary(&changes), vec![("/r/gone".into(), -500)]);
        // the root shrank by 200 overall; growth in the same direction only
        let grown = old.growth(&new, 100, 10);
        assert_eq!(summary(&grown), vec![("/r/gone".into(), 500)]);
        assert_eq!(new.growth(&new, 1, 10), Vec::new());
    }
}
