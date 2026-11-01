//! Sunburst geometry. Each ring is one level below the focused folder; the angle of
//! a segment is proportional to its size.

use super::{NodeId, Tree};

/// One arc of the sunburst. Angles are fractions of the full circle (`0.0..=1.0`),
/// starting at twelve o'clock and going clockwise.
#[derive(Debug, Clone, PartialEq)]
pub struct Segment {
    /// `None` for an aggregate "smaller objects" segment.
    pub id: Option<NodeId>,
    /// Parent entry (for an aggregate: the entry whose children it sums up).
    pub parent: NodeId,
    /// `0` is the first ring around the center.
    pub depth: u32,
    /// Start angle.
    pub start: f64,
    /// End angle.
    pub end: f64,
    /// Branch color in `0.0..1.0`: the middle of the first-ring ancestor.
    pub hue: f64,
    /// Size in bytes.
    pub size: u64,
    /// For an aggregate segment: how many entries it contains.
    pub aggregated: u32,
}

/// Parameters that stay the same through one layout pass.
struct Pass<'a> {
    tree: &'a Tree,
    total: f64,
    rings: u32,
    min_fraction: f64,
    out: Vec<Segment>,
}

impl Tree {
    /// Lays out `rings` rings around `focus`. Children smaller than `min_fraction`
    /// of the circle are merged into one aggregate segment per parent.
    /// Segments come in pre-order: a parent always precedes its children.
    pub fn layout(&self, focus: NodeId, rings: u32, min_fraction: f64) -> Vec<Segment> {
        let Some(f) = self.get(focus) else {
            return Vec::new();
        };
        if f.size == 0 || rings == 0 {
            return Vec::new();
        }
        let mut pass = Pass {
            tree: self,
            total: f.size as f64,
            rings,
            min_fraction,
            out: Vec::new(),
        };
        pass.ring(focus, 0.0, 0, None);
        pass.out
    }
}

impl Pass<'_> {
    fn ring(&mut self, node: NodeId, start: f64, depth: u32, hue: Option<f64>) {
        let mut angle = start;
        let mut small: Option<(f64, u64, u32)> = None; // start, size, count
        for &c in self.tree.children(node) {
            let e = self.tree.entry(c);
            if e.size == 0 {
                continue;
            }
            let frac = e.size as f64 / self.total;
            if frac < self.min_fraction {
                let (_, size, count) = small.get_or_insert((angle, 0, 0));
                *size += e.size;
                *count += 1;
            } else {
                let h = hue.unwrap_or(angle + frac / 2.0);
                self.out.push(Segment {
                    id: Some(c),
                    parent: node,
                    depth,
                    start: angle,
                    end: angle + frac,
                    hue: h,
                    size: e.size,
                    aggregated: 0,
                });
                if depth + 1 < self.rings && !e.children.is_empty() {
                    self.ring(c, angle, depth + 1, Some(h));
                }
            }
            angle += frac;
        }
        if let Some((s, size, count)) = small {
            let frac = size as f64 / self.total;
            self.out.push(Segment {
                id: None,
                parent: node,
                depth,
                start: s,
                end: s + frac,
                hue: hue.unwrap_or(s + frac / 2.0),
                size,
                aggregated: count,
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::tree::tests::sample;

    #[test]
    fn layout_aggregates_small_objects() {
        let t = sample();
        let segs = t.layout(t.root(), 3, 0.06);
        let ring0: Vec<_> = segs.iter().filter(|s| s.depth == 0).collect();
        // a (700), b (200), aggregate (tiny1 + tiny2 = 100 = 10%)
        assert_eq!(ring0.len(), 3);
        let agg = ring0.iter().find(|s| s.id.is_none()).unwrap();
        assert_eq!((agg.size, agg.aggregated), (100, 2));
        assert!((ring0.iter().map(|s| s.end - s.start).sum::<f64>() - 1.0).abs() < 1e-9);
    }

    #[test]
    fn layout_children_inherit_branch_hue() {
        let t = sample();
        let segs = t.layout(t.root(), 3, 0.06);
        let a = segs.iter().find(|s| s.depth == 0).unwrap();
        let ring1: Vec<_> = segs.iter().filter(|s| s.depth == 1).collect();
        assert_eq!(ring1.len(), 2);
        assert!(
            ring1
                .iter()
                .all(|s| (s.hue - a.hue).abs() < f64::EPSILON && s.parent == a.id.unwrap())
        );
    }

    #[test]
    fn layout_of_empty_focus_is_empty() {
        let t = sample();
        assert_eq!(t.layout(t.root(), 0, 0.0), Vec::new());
        assert_eq!(t.layout(999, 3, 0.0), Vec::new());
    }
}
