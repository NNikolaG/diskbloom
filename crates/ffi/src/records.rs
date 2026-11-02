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
    /// For project folders: the last change anywhere in the project outside this item
    /// (Unix seconds); 0 when not applicable.
    pub last_activity: i64,
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
            last_activity: c.project_activity.unwrap_or(0),
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

/// A place that grew or shrank between two scans.
#[derive(Debug, Clone, uniffi::Record)]
pub struct GrowthInfo {
    /// Id in the newer tree, if it still exists.
    pub id: Option<u32>,
    /// Path (firmlinked form).
    pub path: String,
    /// Size in the older scan.
    pub old_size: u64,
    /// Size in the newer scan.
    pub new_size: u64,
}

impl From<&core::Change> for GrowthInfo {
    fn from(c: &core::Change) -> Self {
        Self {
            id: c.id,
            path: user_path(&c.path),
            old_size: c.old_size,
            new_size: c.new_size,
        }
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

/// A broad kind of file; see [`core::Kind`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum FileKind {
    /// Movies and screen recordings.
    Video,
    /// Photos, pictures and design files.
    Images,
    /// Music and recordings.
    Audio,
    /// Archives, installers and disk images.
    Archives,
    /// Office documents, PDFs and text.
    Documents,
    /// Source code and build output.
    Code,
    /// `.app` bundles.
    Apps,
    /// Libraries, frameworks, settings and databases.
    System,
    /// Everything else.
    Other,
}

impl From<core::Kind> for FileKind {
    fn from(k: core::Kind) -> Self {
        match k {
            core::Kind::Video => Self::Video,
            core::Kind::Images => Self::Images,
            core::Kind::Audio => Self::Audio,
            core::Kind::Archives => Self::Archives,
            core::Kind::Documents => Self::Documents,
            core::Kind::Code => Self::Code,
            core::Kind::Apps => Self::Apps,
            core::Kind::System => Self::System,
            core::Kind::Other => Self::Other,
        }
    }
}

impl From<FileKind> for core::Kind {
    fn from(k: FileKind) -> Self {
        match k {
            FileKind::Video => Self::Video,
            FileKind::Images => Self::Images,
            FileKind::Audio => Self::Audio,
            FileKind::Archives => Self::Archives,
            FileKind::Documents => Self::Documents,
            FileKind::Code => Self::Code,
            FileKind::Apps => Self::Apps,
            FileKind::System => Self::System,
            FileKind::Other => Self::Other,
        }
    }
}

/// Total size and number of items of one kind.
#[derive(Debug, Clone, uniffi::Record)]
pub struct KindInfo {
    /// The kind.
    pub kind: FileKind,
    /// Allocated size in bytes.
    pub size: u64,
    /// Number of items (an `.app` bundle counts as one).
    pub count: u64,
}

impl From<core::KindTotal> for KindInfo {
    fn from(t: core::KindTotal) -> Self {
        Self {
            kind: t.kind.into(),
            size: t.size,
            count: t.count,
        }
    }
}

/// A file or folder found by name.
#[derive(Debug, Clone, uniffi::Record)]
pub struct SearchHit {
    /// The entry, as in the largest-files list.
    pub file: FileInfo,
    /// Whether it is a folder (opens on the map).
    pub is_dir: bool,
}

impl SearchHit {
    pub(crate) fn new(tree: &Tree, id: NodeId) -> Option<Self> {
        let is_dir = tree.get(id)?.is_dir;
        FileInfo::new(tree, id).map(|file| Self { file, is_dir })
    }
}
