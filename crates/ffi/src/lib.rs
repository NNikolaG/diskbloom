//! `UniFFI` bridge between `diskbloom-core` and the Swift app.
//!
//! Swift never receives the whole tree (often hundreds of thousands of entries), only
//! ids and what it currently draws ([`DiskTree::layout`], [`DiskTree::children`]).
//! Long operations ([`ScanJob::run`], [`DupeJob::run`], [`DiskTree::rescan`]) block and
//! must be called off the main thread; their progress and cancel methods are safe to
//! call from any thread meanwhile.

mod disk_tree;
mod dupe_job;
mod error;
mod paths;
mod records;
mod scan_job;

pub use disk_tree::DiskTree;
pub use dupe_job::DupeJob;
pub use error::BloomError;
pub use records::{CleanCandidate, DupGroupInfo, FileInfo, NodeInfo, SegmentInfo};
pub use scan_job::ScanJob;

uniffi::setup_scaffolding!();

#[cfg(test)]
mod tests;
