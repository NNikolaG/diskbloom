//! Output: a text tree for the terminal and a self-contained HTML sunburst.

use diskbloom_core::{Entry, NodeId, Tree, human};
use std::fmt::Write;

/// Prints `depth` levels of the tree with at most `top` items per level.
pub fn print_tree(t: &Tree, depth: usize, top: usize) {
    let Some(root) = t.get(t.root()) else { return };
    println!(
        "{}  {}  ({} files)",
        human(root.size),
        root.name,
        root.files
    );
    print_level(t, t.root(), root.size.max(1), depth, top, "");
}

fn print_level(t: &Tree, id: NodeId, total: u64, depth: usize, top: usize, prefix: &str) {
    if depth == 0 {
        return;
    }
    let kids: Vec<(NodeId, &Entry)> = t
        .children(id)
        .iter()
        .filter_map(|&c| Some((c, t.get(c)?)))
        .collect();
    let (shown, rest) = kids.split_at(top.min(kids.len()));
    let rows = shown.len() + usize::from(!rest.is_empty());
    for (i, &(cid, c)) in shown.iter().enumerate() {
        let last = i + 1 == rows;
        let pct = c.size as f64 * 100.0 / total as f64;
        let bar = "█".repeat((pct / 5.0).round().clamp(0.0, 20.0) as usize);
        println!(
            "{prefix}{} {:>9} {pct:>5.1}% {bar:<20} {}{}",
            if last { "└─" } else { "├─" },
            human(c.size),
            c.name,
            if c.is_dir { "/" } else { "" }
        );
        let child_prefix = format!("{prefix}{}", if last { "   " } else { "│  " });
        print_level(t, cid, total, depth - 1, top, &child_prefix);
    }
    if !rest.is_empty() {
        let size: u64 = rest.iter().map(|(_, c)| c.size).sum();
        println!(
            "{prefix}└─ {:>9}        … {} smaller items",
            human(size),
            rest.len()
        );
    }
}

/// A JSON string literal that is also safe inside `<script>`.
fn json_str(out: &mut String, s: &str) {
    out.push('"');
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '<' => out.push_str("\\u003c"), // so a name cannot close the script tag
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

/// Serializes the tree, merging entries smaller than `min_bytes` into "smaller objects".
/// Keys are short to keep large maps small: n(ame), s(ize), f(iles), d(ir), c(hildren),
/// x (aggregate).
fn to_json(t: &Tree, id: NodeId, min_bytes: u64, depth: usize, out: &mut String) {
    let Some(n) = t.get(id) else { return };
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
            let Some(c) = t.get(cid) else { continue };
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

/// The standalone HTML page with the map.
pub fn html(t: &Tree, min_angle_deg: f64, max_depth: usize) -> String {
    let root_size = t.get(t.root()).map_or(0, |r| r.size);
    let min_bytes = (root_size as f64 * min_angle_deg.max(0.0) / 360.0) as u64;
    let mut data = String::new();
    to_json(t, t.root(), min_bytes.max(1), max_depth, &mut data);
    include_str!("sunburst.html").replace("/*DATA*/null", &data)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_str_escapes_script_end_and_controls() {
        let mut out = String::new();
        json_str(&mut out, "a\"b</script>\n");
        assert_eq!(out, r#""a\"b\u003c/script>\u000a""#);
    }
}
