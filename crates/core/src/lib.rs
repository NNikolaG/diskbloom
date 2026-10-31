//! diskbloom-core: paralelni skener diska, arena stablo sa sunburst rasporedom
//! i pravila za ciscenje regenerisivog smeca. Vidi `docs/ARCHITECTURE.md`.

pub mod clean;
pub mod dupes;
pub mod scan;
pub mod tree;

pub use scan::{Node, Scanner, human};
pub use tree::{Entry, NodeId, Segment, Tree};
