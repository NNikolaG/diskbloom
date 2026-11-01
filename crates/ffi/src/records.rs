//! Plain values passed to Swift.

use crate::paths::user_path;
use diskbloom_core::{self as core, NodeId, Tree};

/// One file or folder.
#[derive(Debug, Clone, uniffi::Record)]
pub struct NodeInfo {
    /// Id in the [`crate::DiskTree`].
    pub id: u32,
    /// File name (the scanned path for the root).
    pub name: String,
    /// Allocated size in bytes.
    pub size: u64,
    /// Number of files below.
    pub files: u64,
    /// Whether it is a folder.
    pub is_dir: bool,
    /// Whether it has children to zoom into.
    pub has_children: bool,
}

impl NodeInfo {
    pub(crate) fn new(tree: &Tree, id: NodeId) -> Option<Self> {
        tree.get(id).map(|e| Self {
            id,
            name: e.name.clone(),
            size: e.size,
            files: e.files,
            is_dir: e.is_dir,
            has_children: !e.children.is_empty(),
        })
    }
}

/// One arc of the sunburst; see [`core::Segment`].
#[derive(Debug, Clone, uniffi::Record)]
pub struct SegmentInfo {
    /// `None` for an aggregate "smaller objects" segment.
    pub id: Option<u32>,
    /// Parent entry.
    pub parent: u32,
    /// Name, or "N smaller objects".
    pub name: String,
    /// Ring, `0` around the center.
    pub depth: u32,
    /// Start angle as a fraction of the circle, from twelve o'clock clockwise.
    pub start: f64,
    /// End angle.
    pub end: f64,
    /// Branch color, `0.0..1.0`.
    pub hue: f64,
    /// Size in bytes.
    pub size: u64,
    /// Whether it is a folder.
    pub is_dir: bool,
    /// Whether it has children to zoom into.
    pub has_children: bool,
    /// For an aggregate: how many entries it contains.
    pub aggregated: u32,
}

impl SegmentInfo {
    pub(crate) fn new(tree: &Tree, s: &core::Segment) -> Self {
        let e = s.id.and_then(|id| tree.get(id));
        Self {
            id: s.id,
            parent: s.parent,
            name: e.map_or_else(
                || format!("{} smaller objects", s.aggregated),
                |e| e.name.clone(),
            ),
            depth: s.depth,
            start: s.start,
            end: s.end,
            hue: s.hue,
            size: s.size,
            is_dir: e.is_some_and(|e| e.is_dir),
            has_children: e.is_some_and(|e| !e.children.is_empty()),
            aggregated: s.aggregated,
        }
    }
}

/// A Smart Clean candidate.
#[derive(Debug, Clone, uniffi::Record)]
pub struct CleanCandidate {
    /// Id in the [`crate::DiskTree`].
    pub id: u32,
    /// Path for the Trash and Finder (firmlinked form).
    pub path: String,
    /// Allocated size in bytes.
    pub size: u64,
    /// Category id, e.g. `rust-build`; see [`core::clean::Category`].
    pub category: String,
    /// Regenerates on its own (builds, caches); otherwise the user should review it.
    pub safe: bool,
    /// Whether it is a folder.
    pub is_dir: bool,
}

impl From<core::clean::Candidate> for CleanCandidate {
    fn from(c: core::clean::Candidate) -> Self {
        Self {
            id: c.id,
            path: user_path(&c.path),
            size: c.size,
            category: c.category.id().to_owned(),
            safe: c.is_safe(),
            is_dir: c.is_dir,
        }
    }
}

/// A file in the largest-files and duplicates lists.
#[derive(Debug, Clone, uniffi::Record)]
pub struct FileInfo {
    /// Id in the [`crate::DiskTree`].
    pub id: u32,
    /// File name.
    pub name: String,
    /// Path for the Trash, Finder and Quick Look (firmlinked form).
    pub path: String,
    /// Allocated size in bytes.
    pub size: u64,
}

impl FileInfo {
    pub(crate) fn new(tree: &Tree, id: NodeId) -> Option<Self> {
        tree.get(id).map(|e| Self {
            id,
            name: e.name.clone(),
            path: user_path(&tree.path(id)),
            size: e.size,
        })
    }
}

/// Files with identical content.
#[derive(Debug, Clone, uniffi::Record)]
pub struct DupGroupInfo {
    /// Size of one file.
    pub size: u64,
    /// Bytes freed by keeping one copy.
    pub wasted: u64,
    /// The copies.
    pub files: Vec<FileInfo>,
}
