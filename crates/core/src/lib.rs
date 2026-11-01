//! Diskbloom core: a parallel disk scanner, an arena tree with a sunburst layout,
//! cleanup rules for regenerable data and a duplicate finder.
//!
//! The typical flow is [`Scanner`] → [`Node`] → [`Tree`], then [`Tree::layout`] for
//! drawing, [`clean::find`] for Smart Clean and [`dupes::DupeFinder`] for duplicates.
//! See `docs/ARCHITECTURE.md` for the big picture.

pub mod clean;
pub mod dupes;
pub mod scan;
pub mod tree;
pub mod volume;

pub use scan::{Node, Scanner, human};
pub use tree::{Entry, NodeId, Segment, Tree};
