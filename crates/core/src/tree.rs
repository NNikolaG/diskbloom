//! Arena stablo: ravna lista cvorova adresiranih preko `NodeId`.
//!
//! Ovo je model koji UI koristi: lako se prenosi preko FFI granice (samo brojevi),
//! podrzava lokalno azuriranje posle brisanja bez ponovnog skeniranja,
//! i racuna sunburst raspored (`layout`) tako da Swift samo crta.

use crate::scan::Node;
use std::path::{Component, Path, PathBuf};

pub type NodeId = u32;

#[derive(Debug, Clone)]
pub struct Entry {
    pub name: String,
    pub size: u64,
    pub files: u64,
    pub is_dir: bool,
    pub parent: Option<NodeId>,
    /// Sortirano po velicini, najvece prvo.
    pub children: Vec<NodeId>,
}

#[derive(Debug, Clone)]
pub struct Tree {
    entries: Vec<Entry>,
    root_path: PathBuf,
}

/// Jedan luk sunburst-a. Uglovi su u razlomcima kruga (0.0..=1.0).
#[derive(Debug, Clone, PartialEq)]
pub struct Segment {
    /// `None` = zbirni segment "smaller objects".
    pub id: Option<NodeId>,
    /// Roditelj u stablu (za zbirni segment: cvor ciju decu sabira).
    pub parent: NodeId,
    /// 0 = prvi prsten oko centra.
    pub depth: u32,
    pub start: f64,
    pub end: f64,
    /// Boja grane: sredina pretka u prvom prstenu, 0.0..1.0.
    pub hue: f64,
    pub size: u64,
    /// Za zbirni segment: koliko objekata sadrzi.
    pub aggregated: u32,
}

impl Tree {
    /// `root_path` je apsolutna putanja skeniranog korena.
    pub fn from_node(root: Node, root_path: PathBuf) -> Self {
        let mut entries = Vec::new();
        push(&mut entries, root, None);
        Tree { entries, root_path }
    }

    pub fn root(&self) -> NodeId {
        0
    }

    pub fn root_path(&self) -> &Path {
        &self.root_path
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn get(&self, id: NodeId) -> Option<&Entry> {
        self.entries.get(id as usize)
    }

    fn e(&self, id: NodeId) -> &Entry {
        &self.entries[id as usize]
    }

    pub fn children(&self, id: NodeId) -> &[NodeId] {
        self.get(id).map(|e| e.children.as_slice()).unwrap_or(&[])
    }

    /// Lanac od korena do `id` (ukljucujuci oba).
    pub fn ancestors(&self, id: NodeId) -> Vec<NodeId> {
        let mut v = vec![id];
        let mut cur = id;
        while let Some(p) = self.get(cur).and_then(|e| e.parent) {
            v.push(p);
            cur = p;
        }
        v.reverse();
        v
    }

    pub fn path(&self, id: NodeId) -> PathBuf {
        let mut p = self.root_path.clone();
        for a in self.ancestors(id).into_iter().skip(1) {
            p.push(&self.e(a).name);
        }
        p
    }

    /// Nalazi cvor po apsolutnoj putanji.
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
                .find(|&&c| self.e(c).name == name)?;
        }
        Some(cur)
    }

    /// Uklanja cvor (posle brisanja sa diska) i azurira velicine predaka.
    /// Vraca broj oslobodjenih bajtova. Koren se ne moze ukloniti.
    pub fn remove(&mut self, id: NodeId) -> u64 {
        let Some(entry) = self.get(id) else { return 0 };
        let Some(parent) = entry.parent else { return 0 };
        let (size, files) = (entry.size, entry.files);
        self.entries[parent as usize].children.retain(|&c| c != id);
        self.entries[id as usize].parent = None;
        let mut cur = Some(parent);
        while let Some(p) = cur {
            let e = &mut self.entries[p as usize];
            e.size = e.size.saturating_sub(size);
            e.files = e.files.saturating_sub(files);
            cur = e.parent;
            if let Some(gp) = cur {
                self.resort(gp);
            }
        }
        size
    }

    fn resort(&mut self, id: NodeId) {
        let mut kids = std::mem::take(&mut self.entries[id as usize].children);
        kids.sort_by_key(|&k| std::cmp::Reverse(self.e(k).size));
        self.entries[id as usize].children = kids;
    }

    /// Racuna sunburst oko `focus`: `rings` prstenova, objekti manji od
    /// `min_fraction` kruga spajaju se u jedan zbirni segment po roditelju.
    pub fn layout(&self, focus: NodeId, rings: u32, min_fraction: f64) -> Vec<Segment> {
        let mut out = Vec::new();
        let Some(f) = self.get(focus) else { return out };
        if f.size == 0 || rings == 0 {
            return out;
        }
        self.layout_rec(
            focus,
            f.size as f64,
            0.0,
            0,
            rings,
            min_fraction,
            None,
            &mut out,
        );
        out
    }

    #[allow(clippy::too_many_arguments)]
    fn layout_rec(
        &self,
        node: NodeId,
        total: f64,
        start: f64,
        depth: u32,
        rings: u32,
        min_fraction: f64,
        hue: Option<f64>,
        out: &mut Vec<Segment>,
    ) {
        let mut a = start;
        let (mut small_start, mut small_size, mut small_n) = (None, 0u64, 0u32);
        for &c in self.children(node) {
            let e = self.e(c);
            if e.size == 0 {
                continue;
            }
            let frac = e.size as f64 / total;
            if frac < min_fraction {
                small_start.get_or_insert(a);
                small_size += e.size;
                small_n += 1;
                a += frac;
                continue;
            }
            let h = hue.unwrap_or(a + frac / 2.0);
            out.push(Segment {
                id: Some(c),
                parent: node,
                depth,
                start: a,
                end: a + frac,
                hue: h,
                size: e.size,
                aggregated: 0,
            });
            if depth + 1 < rings && !e.children.is_empty() {
                self.layout_rec(c, total, a, depth + 1, rings, min_fraction, Some(h), out);
            }
            a += frac;
        }
        if let Some(s) = small_start {
            let frac = small_size as f64 / total;
            out.push(Segment {
                id: None,
                parent: node,
                depth,
                start: s,
                end: s + frac,
                hue: hue.unwrap_or(s + frac / 2.0),
                size: small_size,
                aggregated: small_n,
            });
        }
    }
}

fn push(entries: &mut Vec<Entry>, n: Node, parent: Option<NodeId>) -> NodeId {
    let id = entries.len() as NodeId;
    entries.push(Entry {
        name: n.name,
        size: n.size,
        files: n.files,
        is_dir: n.is_dir,
        parent,
        children: Vec::with_capacity(n.children.len()),
    });
    // Deca su vec sortirana u skeneru.
    for c in n.children {
        let cid = push(entries, c, Some(id));
        entries[id as usize].children.push(cid);
    }
    id
}

#[cfg(test)]
mod tests {
    use super::*;

    fn leaf(name: &str, size: u64) -> Node {
        Node {
            name: name.into(),
            size,
            files: 1,
            is_dir: false,
            children: vec![],
        }
    }
    fn dir(name: &str, children: Vec<Node>) -> Node {
        let size = children.iter().map(|c| c.size).sum();
        let files = children.iter().map(|c| c.files).sum();
        let mut children = children;
        children.sort_by_key(|c| std::cmp::Reverse(c.size));
        Node {
            name: name.into(),
            size,
            files,
            is_dir: true,
            children,
        }
    }
    fn sample() -> Tree {
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

    #[test]
    fn find_and_path_roundtrip() {
        let t = sample();
        let a2 = t.find(Path::new("/r/a/a2")).unwrap();
        assert_eq!(t.path(a2), PathBuf::from("/r/a/a2"));
        assert_eq!(t.find(Path::new("/r/nope")), None);
        assert_eq!(t.find(Path::new("/r")), Some(0));
    }

    #[test]
    fn layout_aggregates_small_objects() {
        let t = sample();
        let segs = t.layout(t.root(), 3, 0.06);
        let ring0: Vec<_> = segs.iter().filter(|s| s.depth == 0).collect();
        // a (700), b (200), zbirno (tiny1 + tiny2 = 100 = 10%)
        assert_eq!(ring0.len(), 3);
        let agg = ring0.iter().find(|s| s.id.is_none()).unwrap();
        assert_eq!((agg.size, agg.aggregated), (100, 2));
        assert!((ring0.iter().map(|s| s.end - s.start).sum::<f64>() - 1.0).abs() < 1e-9);
        // deca od "a" su u drugom prstenu i nasledjuju boju
        let a = ring0[0];
        let ring1: Vec<_> = segs.iter().filter(|s| s.depth == 1).collect();
        assert_eq!(ring1.len(), 2);
        assert!(
            ring1
                .iter()
                .all(|s| s.hue == a.hue && s.parent == a.id.unwrap())
        );
    }

    #[test]
    fn remove_updates_ancestors_and_order() {
        let mut t = sample();
        let a1 = t.find(Path::new("/r/a/a1")).unwrap();
        assert_eq!(t.remove(a1), 600);
        let a = t.find(Path::new("/r/a")).unwrap();
        assert_eq!(t.get(a).unwrap().size, 100);
        assert_eq!(t.get(0).unwrap().size, 400);
        // "b" (200) je sada veci od "a" (100)
        assert_eq!(t.get(t.children(0)[0]).unwrap().name, "b");
        assert_eq!(t.find(Path::new("/r/a/a1")), None);
        assert_eq!(t.remove(0), 0);
    }
}
