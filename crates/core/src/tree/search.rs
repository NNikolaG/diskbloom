//! Finding files and folders by name.
//!
//! Matching ignores case and diacritics, like `localizedStandardContains` in Swift:
//! "cevap" finds "Ćevapi.txt", in both the composed and the decomposed form macOS may
//! store it in.

use super::{NodeId, Tree};
use std::cmp::Reverse;
use std::collections::BinaryHeap;

impl Tree {
    /// Files and folders whose name contains `query`, ignoring case and diacritics,
    /// largest first, at most `limit`. The root itself is not included. An empty (or
    /// all-whitespace) query finds nothing.
    pub fn search(&self, query: &str, limit: usize) -> Vec<NodeId> {
        let needle = fold(query.trim());
        if needle.is_empty() || limit == 0 {
            return Vec::new();
        }
        let mut heap = BinaryHeap::with_capacity(limit + 1);
        let mut folded = String::new();
        let mut stack: Vec<NodeId> = self.children(self.root()).to_vec();
        while let Some(id) = stack.pop() {
            let e = self.entry(id);
            // Once the list is full, nothing this size or smaller (and nothing below
            // it) can get in.
            if heap.len() == limit && heap.peek().is_some_and(|Reverse((s, _))| e.size <= *s) {
                continue;
            }
            folded.clear();
            fold_into(&e.name, &mut folded);
            if folded.contains(needle.as_str()) {
                heap.push(Reverse((e.size, id)));
                if heap.len() > limit {
                    heap.pop();
                }
            }
            stack.extend_from_slice(&e.children);
        }
        heap.into_sorted_vec()
            .into_iter()
            .map(|Reverse((_, id))| id)
            .collect()
    }
}

/// `s` lowercased, without diacritics.
fn fold(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    fold_into(s, &mut out);
    out
}

fn fold_into(s: &str, out: &mut String) {
    if s.is_ascii() {
        out.extend(s.chars().map(|c| c.to_ascii_lowercase()));
        return;
    }
    for c in s.chars().flat_map(char::to_lowercase) {
        match c {
            // Combining marks, as in a decomposed "c" + U+0301.
            '\u{300}'..='\u{36f}' => {}
            '\u{c0}'..='\u{17f}' => out.push(LATIN[c as usize - 0xc0]),
            _ => out.push(c),
        }
    }
}

/// Base letters for U+00C0..=U+017F (Latin-1 Supplement and Latin Extended-A),
/// lowercase. Letters without a decomposition keep their own form, except đ, ł, ø, ħ
/// and ŧ, which are commonly typed without the stroke.
const LATIN: [char; 192] = [
    'a', 'a', 'a', 'a', 'a', 'a', 'æ', 'c', 'e', 'e', 'e', 'e', 'i', 'i', 'i', 'i', 'ð', 'n', 'o',
    'o', 'o', 'o', 'o', '×', 'o', 'u', 'u', 'u', 'u', 'y', 'þ', 'ß', 'a', 'a', 'a', 'a', 'a', 'a',
    'æ', 'c', 'e', 'e', 'e', 'e', 'i', 'i', 'i', 'i', 'ð', 'n', 'o', 'o', 'o', 'o', 'o', '÷', 'o',
    'u', 'u', 'u', 'u', 'y', 'þ', 'y', 'a', 'a', 'a', 'a', 'a', 'a', 'c', 'c', 'c', 'c', 'c', 'c',
    'c', 'c', 'd', 'd', 'd', 'd', 'e', 'e', 'e', 'e', 'e', 'e', 'e', 'e', 'e', 'e', 'g', 'g', 'g',
    'g', 'g', 'g', 'g', 'g', 'h', 'h', 'h', 'h', 'i', 'i', 'i', 'i', 'i', 'i', 'i', 'i', 'i', 'ı',
    'ĳ', 'ĳ', 'j', 'j', 'k', 'k', 'ĸ', 'l', 'l', 'l', 'l', 'l', 'l', 'ŀ', 'ŀ', 'l', 'l', 'n', 'n',
    'n', 'n', 'n', 'n', 'ŉ', 'ŋ', 'ŋ', 'o', 'o', 'o', 'o', 'o', 'o', 'œ', 'œ', 'r', 'r', 'r', 'r',
    'r', 'r', 's', 's', 's', 's', 's', 's', 's', 's', 't', 't', 't', 't', 't', 't', 'u', 'u', 'u',
    'u', 'u', 'u', 'u', 'u', 'u', 'u', 'u', 'u', 'w', 'w', 'y', 'y', 'y', 'z', 'z', 'z', 'z', 'z',
    'z', 'ſ',
];

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tree::tests::{dir, leaf};
    use std::path::PathBuf;

    fn tree() -> Tree {
        let root = dir(
            "/r",
            vec![
                dir(
                    "Photos",
                    vec![leaf("Ćevapi.JPG", 300), leaf("photo-1.jpg", 100)],
                ),
                dir("projects", vec![leaf("photon.rs", 50)]),
                leaf("Cafe\u{301} menu.pdf", 40),
                leaf("notes.txt", 10),
            ],
        );
        Tree::from_node(root, PathBuf::from("/r"))
    }

    fn names(t: &Tree, query: &str, limit: usize) -> Vec<String> {
        t.search(query, limit)
            .into_iter()
            .map(|id| t.get(id).unwrap().name.clone())
            .collect()
    }

    #[test]
    fn search_ignores_case_and_sorts_by_size() {
        let t = tree();
        assert_eq!(
            names(&t, "PHOTO", 10),
            vec!["Photos", "photo-1.jpg", "photon.rs"]
        );
    }

    #[test]
    fn search_ignores_diacritics_in_both_forms() {
        let t = tree();
        assert_eq!(names(&t, "cevap", 10), vec!["Ćevapi.JPG"]);
        assert_eq!(names(&t, "ćevap", 10), vec!["Ćevapi.JPG"]);
        assert_eq!(names(&t, "café", 10), vec!["Cafe\u{301} menu.pdf"]);
        assert_eq!(names(&t, "cafe", 10), vec!["Cafe\u{301} menu.pdf"]);
    }

    #[test]
    fn search_keeps_only_the_largest_results() {
        let t = tree();
        assert_eq!(names(&t, "o", 2), vec!["Photos", "photo-1.jpg"]);
    }

    #[test]
    fn search_with_empty_query_finds_nothing() {
        let t = tree();
        assert_eq!(t.search("  ", 10), Vec::<NodeId>::new());
        assert_eq!(t.search("photo", 0), Vec::<NodeId>::new());
    }

    #[test]
    fn search_does_not_match_the_root() {
        let t = tree();
        assert_eq!(names(&t, "/r", 10), Vec::<String>::new());
    }

    #[test]
    fn fold_strips_serbian_diacritics() {
        assert_eq!(fold("ČĆŠĐŽ čćšđž"), "ccsdz ccsdz");
    }
}
