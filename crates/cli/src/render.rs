//! Vizualizacija (sloj 4): tekstualno stablo i samostalni HTML sunburst.

use diskbloom_core::{NodeId, Tree, human};
use std::fmt::Write;

pub fn print_tree(t: &Tree, depth: usize, top: usize) {
    let root = t.get(t.root()).unwrap();
    println!(
        "{}  {}  ({} fajlova)",
        human(root.size),
        root.name,
        root.files
    );
    walk(t, t.root(), root.size.max(1), depth, top, "");
}

fn walk(t: &Tree, id: NodeId, total: u64, depth: usize, top: usize, prefix: &str) {
    if depth == 0 {
        return;
    }
    let kids = t.children(id);
    let shown: Vec<_> = kids
        .iter()
        .take(top)
        .map(|&c| (c, t.get(c).unwrap()))
        .collect();
    let rest: Vec<_> = kids.iter().skip(top).map(|&c| t.get(c).unwrap()).collect();
    let count = shown.len() + usize::from(!rest.is_empty());
    for (i, (cid, c)) in shown.iter().enumerate() {
        let last = i + 1 == count;
        let pct = c.size as f64 * 100.0 / total as f64;
        let bar = "█".repeat(((pct / 5.0).round() as usize).min(20));
        println!(
            "{prefix}{} {:>9} {:>5.1}% {:<20} {}{}",
            if last { "└─" } else { "├─" },
            human(c.size),
            pct,
            bar,
            c.name,
            if c.is_dir { "/" } else { "" }
        );
        let np = format!("{prefix}{}", if last { "   " } else { "│  " });
        walk(t, *cid, total, depth - 1, top, &np);
    }
    if !rest.is_empty() {
        let s: u64 = rest.iter().map(|c| c.size).sum();
        println!(
            "{prefix}└─ {:>9}        … {} manjih objekata",
            human(s),
            rest.len()
        );
    }
}

fn json_str(out: &mut String, s: &str) {
    out.push('"');
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '<' => out.push_str("\\u003c"), // da </script> ne prekine HTML
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

/// Serijalizuje stablo, spajajuci cvorove manje od `min_bytes` u "smaller objects".
fn to_json(t: &Tree, id: NodeId, min_bytes: u64, depth: usize, out: &mut String) {
    let n = t.get(id).unwrap();
    out.push_str("{\"n\":");
    json_str(out, &n.name);
    let _ = write!(out, ",\"s\":{},\"f\":{}", n.size, n.files);
    if n.is_dir {
        out.push_str(",\"d\":1");
    }
    if depth > 0 && !n.children.is_empty() {
        out.push_str(",\"c\":[");
        let mut first = true;
        let (mut small_size, mut small_count) = (0u64, 0usize);
        for &cid in &n.children {
            let c = t.get(cid).unwrap();
            if c.size < min_bytes {
                small_size += c.size;
                small_count += 1;
                continue;
            }
            if !first {
                out.push(',');
            }
            first = false;
            to_json(t, cid, min_bytes, depth - 1, out);
        }
        if small_count > 0 && small_size > 0 {
            if !first {
                out.push(',');
            }
            let _ = write!(
                out,
                "{{\"n\":\"{small_count} smaller objects\",\"s\":{small_size},\"x\":1}}"
            );
        }
        out.push(']');
    }
    out.push('}');
}

pub fn html(t: &Tree, min_angle_deg: f64, max_depth: usize) -> String {
    let root = t.get(t.root()).unwrap();
    let min_bytes = (root.size as f64 * min_angle_deg / 360.0) as u64;
    let mut data = String::new();
    to_json(t, t.root(), min_bytes.max(1), max_depth, &mut data);
    include_str!("sunburst.html").replace("/*DATA*/null", &data)
}
