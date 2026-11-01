//! Arena tree: a flat list of entries addressed by [`NodeId`].
//!
//! This is the model the app works with. Only numbers cross the FFI boundary, the
//! tree can be updated in place after a delete or a folder refresh without a full
//! rescan, and the sunburst geometry is computed here ([`Tree::layout`]) so the UI
//! only draws.

mod layout;

pub use layout::Segment;

use crate::scan::Node;
use std::cmp::Reverse;
use std::collections::{BinaryHeap, HashMap};
use std::path::{Component, Path, PathBuf};

/// Index of an entry in a [`Tree`]. Ids stay valid after removals; removed entries
/// are detached (see [`Tree::is_attached`]) rather than reused.
pub type NodeId = u32;

/// One file or folder in a [`Tree`].
#[derive(Debug, Clone)]
pub struct Entry {
    /// File name (the full scanned path for the root).
    pub name: String,
    /// Allocated size in bytes, including descendants.
    pub size: u64,
    /// Number of files below this entry.
    pub files: u64,
    /// Whether this is a folder.
    pub is_dir: bool,
    /// `None` for the root and for detached entries.
    pub parent: Option<NodeId>,
    /// Sorted by size, largest first.
    pub children: Vec<NodeId>,
}

/// A scanned folder tree.
#[derive(Debug, Clone)]
pub struct Tree {
    entries: Vec<Entry>,
    root_path: PathBuf,
}

impl Tree {
    /// Flattens a scan result. `root_path` is the absolute path that was scanned.
    pub fn from_node(root: Node, root_path: PathBuf) -> Self {
        let mut entries = Vec::new();
        push(&mut entries, root, None);
        Tree { entries, root_path }
    }

    /// The root entry, always `0`.
    pub fn root(&self) -> NodeId {
        0
    }

    /// The absolute path that was scanned.
    pub fn root_path(&self) -> &Path {
        &self.root_path
    }

    /// Number of entries, including detached ones.
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// Whether the tree has no entries.
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// The entry for `id`, if it exists.
    pub fn get(&self, id: NodeId) -> Option<&Entry> {
        self.entries.get(id as usize)
    }

    /// For ids that come from the tree itself, which are always valid.
    fn entry(&self, id: NodeId) -> &Entry {
        &self.entries[id as usize]
    }

    /// Children of `id`, largest first. Empty for unknown ids.
    pub fn children(&self, id: NodeId) -> &[NodeId] {
        self.get(id).map_or(&[], |e| e.children.as_slice())
    }

    /// The chain from the root down to `id`, both included.
    pub fn ancestors(&self, id: NodeId) -> Vec<NodeId> {
        let mut chain = vec![id];
        let mut cur = id;
        while let Some(parent) = self.get(cur).and_then(|e| e.parent) {
            chain.push(parent);
            cur = parent;
        }
        chain.reverse();
        chain
    }

    /// Absolute path of `id`.
    pub fn path(&self, id: NodeId) -> PathBuf {
        let mut path = self.root_path.clone();
        for a in self.ancestors(id).into_iter().skip(1) {
            path.push(&self.entry(a).name);
        }
        path
    }

    /// Finds an entry by absolute path.
    pub fn find(&self, path: &Path) -> Option<NodeId> {
        let rel = path.strip_prefix(&self.root_path).ok()?;
        let mut cur = self.root();
        for comp in rel.components() {
            let Component::Normal(name) = comp else {
                return None;
            };
            let name = name.to_string_lossy();
            cur = *self
                .children(cur)
                .iter()
                .find(|&&c| self.entry(c).name == name)?;
        }
        Some(cur)
    }

    /// Removes an entry after it was deleted from disk and updates the sizes of its
    /// ancestors. Returns the bytes freed. The root cannot be removed.
    pub fn remove(&mut self, id: NodeId) -> u64 {
        let Some(entry) = self.get(id) else { return 0 };
        let Some(parent) = entry.parent else { return 0 };
        let (size, files) = (entry.size, entry.files);
        self.entries[parent as usize].children.retain(|&c| c != id);
        self.entries[id as usize].parent = None;
        self.adjust_ancestors(
            parent,
            |s| s.saturating_sub(size),
            |f| f.saturating_sub(files),
        );
        size
    }

    /// Whether the entry is still part of the tree (neither it nor an ancestor was removed).
    pub fn is_attached(&self, id: NodeId) -> bool {
        self.ancestors(id).first() == Some(&self.root())
    }

    /// Replaces the subtree at `id` with a fresh scan of that folder and adjusts the
    /// ancestors by the difference. Returns the id of the new entry.
    pub fn replace_subtree(&mut self, id: NodeId, mut node: Node) -> NodeId {
        let Some(old) = self.get(id) else { return id };
        // The scanner names its root by full path; keep the short name.
        node.name.clone_from(&old.name);
        let (old_size, old_files) = (old.size, old.files);
        let Some(parent) = old.parent else {
            let root_path = std::mem::take(&mut self.root_path);
            *self = Tree::from_node(node, root_path);
            return self.root();
        };
        let (new_size, new_files) = (node.size, node.files);
        let new_id = push(&mut self.entries, node, Some(parent));
        if let Some(slot) = self.entries[parent as usize]
            .children
            .iter_mut()
            .find(|c| **c == id)
        {
            *slot = new_id;
        }
        self.entries[id as usize].parent = None;
        self.adjust_ancestors(
            parent,
            |s| (s + new_size).saturating_sub(old_size),
            |f| (f + new_files).saturating_sub(old_files),
        );
        new_id
    }

    /// Applies new totals from `from` up to the root, keeping every child list sorted.
    fn adjust_ancestors(
        &mut self,
        from: NodeId,
        size: impl Fn(u64) -> u64,
        files: impl Fn(u64) -> u64,
    ) {
        let mut cur = Some(from);
        while let Some(id) = cur {
            let e = &mut self.entries[id as usize];
            e.size = size(e.size);
            e.files = files(e.files);
            self.sort_children(id);
            cur = self.entries[id as usize].parent;
        }
    }

    fn sort_children(&mut self, id: NodeId) {
        let mut kids = std::mem::take(&mut self.entries[id as usize].children);
        kids.sort_by_key(|&k| Reverse(self.entry(k).size));
        self.entries[id as usize].children = kids;
    }

    /// Visits every file of at least `min_size` bytes. Folders smaller than that are
    /// skipped entirely, since nothing inside can be larger.
    fn files_at_least(&self, min_size: u64, mut f: impl FnMut(NodeId, &Entry)) {
        let mut stack = vec![self.root()];
        while let Some(id) = stack.pop() {
            let e = self.entry(id);
            if e.size < min_size {
                continue;
            }
            if e.is_dir {
                stack.extend(e.children.iter().copied());
            } else {
                f(id, e);
            }
        }
    }

    /// The `limit` largest files of at least `min_size` bytes, largest first.
    pub fn largest_files(&self, limit: usize, min_size: u64) -> Vec<NodeId> {
        let mut heap = BinaryHeap::with_capacity(limit + 1);
        self.files_at_least(min_size, |id, e| {
            heap.push(Reverse((e.size, id)));
            if heap.len() > limit {
                heap.pop();
            }
        });
        // Ascending order of Reverse(..) is descending size.
        heap.into_sorted_vec()
            .into_iter()
            .map(|Reverse((_, id))| id)
            .collect()
    }

    /// Files of at least `min_size` bytes grouped by size, only groups of two or more.
    /// This is the first step of the duplicate search.
    pub fn same_size_groups(&self, min_size: u64) -> Vec<Vec<NodeId>> {
        let mut by_size: HashMap<u64, Vec<NodeId>> = HashMap::new();
        self.files_at_least(min_size, |id, e| {
            by_size.entry(e.size).or_default().push(id);
        });
        by_size.into_values().filter(|v| v.len() > 1).collect()
    }
}

fn push(entries: &mut Vec<Entry>, node: Node, parent: Option<NodeId>) -> NodeId {
    let id = entries.len() as NodeId;
    entries.push(Entry {
        name: node.name,
        size: node.size,
        files: node.files,
        is_dir: node.is_dir,
        parent,
        children: Vec::with_capacity(node.children.len()),
    });
    // Children are already sorted by the scanner.
    for child in node.children {
        let cid = push(entries, child, Some(id));
        entries[id as usize].children.push(cid);
    }
    id
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    pub fn leaf(name: &str, size: u64) -> Node {
        Node {
            name: name.into(),
            size,
            files: 1,
            is_dir: false,
            children: vec![],
        }
    }

    pub fn dir(name: &str, mut children: Vec<Node>) -> Node {
        children.sort_by_key(|c| Reverse(c.size));
        Node {
            name: name.into(),
            size: children.iter().map(|c| c.size).sum(),
            files: children.iter().map(|c| c.files).sum(),
            is_dir: true,
            children,
        }
    }

    /// `/r` = a/ (a1 600, a2 100), b 200, tiny1 50, tiny2 50.
    pub fn sample() -> Tree {
        let root = dir(
            "/r",
            vec![
                dir("a", vec![leaf("a1", 600), leaf("a2", 100)]),
                leaf("b", 200),
                leaf("tiny1", 50),
                leaf("tiny2", 50),
            ],
        );
        Tree::from_node(root, PathBuf::from("/r"))
    }

    fn name(t: &Tree, id: NodeId) -> &str {
        &t.get(id).unwrap().name
    }

    #[test]
    fn find_and_path_round_trip() {
        let t = sample();
        let a2 = t.find(Path::new("/r/a/a2")).unwrap();
        assert_eq!(t.path(a2), PathBuf::from("/r/a/a2"));
        assert_eq!(t.find(Path::new("/r/nope")), None);
        assert_eq!(t.find(Path::new("/r")), Some(0));
    }

    #[test]
    fn largest_files_returns_biggest_first() {
        let t = sample();
        let names: Vec<_> = t
            .largest_files(2, 0)
            .into_iter()
            .map(|id| name(&t, id))
            .collect();
        assert_eq!(names, vec!["a1", "b"]);
    }

    #[test]
    fn same_size_groups_needs_two_files_above_minimum() {
        let t = sample();
        let groups = t.same_size_groups(1);
        assert_eq!(groups.len(), 1); // tiny1 + tiny2
        assert_eq!(groups[0].len(), 2);
        assert_eq!(t.same_size_groups(60), Vec::<Vec<NodeId>>::new());
    }

    #[test]
    fn replace_subtree_adjusts_sizes() {
        let mut t = sample();
        let a = t.find(Path::new("/r/a")).unwrap();
        let fresh = dir(
            "/r/a",
            vec![leaf("a1", 600), leaf("a2", 100), leaf("a3", 1000)],
        );
        let new_a = t.replace_subtree(a, fresh);
        assert_ne!(new_a, a);
        assert_eq!(name(&t, new_a), "a"); // short name, not the scanned path
        assert_eq!(t.get(0).unwrap().size, 2000);
        assert_eq!(t.find(Path::new("/r/a/a3")), Some(t.children(new_a)[0]));
        assert!(!t.is_attached(a));
        assert!(t.is_attached(new_a));
    }

    #[test]
    fn replace_root_rebuilds_tree() {
        let mut t = sample();
        let id = t.replace_subtree(0, dir("/r", vec![leaf("only", 5)]));
        assert_eq!(id, 0);
        assert_eq!(name(&t, 0), "/r");
        assert_eq!(t.root_path(), Path::new("/r"));
        assert_eq!(t.len(), 2);
    }

    #[test]
    fn remove_updates_ancestors_and_order() {
        let mut t = sample();
        let a1 = t.find(Path::new("/r/a/a1")).unwrap();
        assert_eq!(t.remove(a1), 600);
        let a = t.find(Path::new("/r/a")).unwrap();
        assert_eq!(t.get(a).unwrap().size, 100);
        assert_eq!(t.get(0).unwrap().size, 400);
        // b (200) is now larger than a (100)
        assert_eq!(name(&t, t.children(0)[0]), "b");
        assert_eq!(t.find(Path::new("/r/a/a1")), None);
        assert_eq!(t.remove(0), 0);
    }
}
