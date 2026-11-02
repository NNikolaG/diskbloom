//! The `getattrlistbulk` path must give exactly the tree the portable
//! `readdir` + `fstatat` path gives.

use super::*;
use std::os::macos::fs::MetadataExt as _;
use std::process::Command;

/// `st_flags` bit of a file stored compressed (`<sys/stat.h>`).
const UF_COMPRESSED: u32 = 0x20;

fn scan(root: &Path, cross_fs: bool, bulk: bool) -> (Node, u64) {
    let scanner = Scanner::with_bulk(root.to_path_buf(), cross_fs, bulk).unwrap();
    let node = scanner.scan().unwrap();
    (node, scanner.errors())
}

/// How strictly sizes are compared below the root.
#[derive(Clone, Copy)]
enum Sizes {
    /// Every node, except files named `linked-*` (which link of a hard-linked file is
    /// counted depends on thread timing).
    Exact,
    /// Only the root: real trees can have hard links in different folders.
    RootOnly,
}

fn by_name(n: &Node) -> Vec<&Node> {
    let mut c: Vec<&Node> = n.children.iter().collect();
    c.sort_by(|x, y| x.name.cmp(&y.name));
    c
}

/// Collects every difference between `a` and `b`, children matched by name.
fn diff(a: &Node, b: &Node, path: &str, sizes: Sizes, root: bool, out: &mut Vec<String>) {
    let linked = !a.is_dir && a.name.starts_with("linked-");
    let check_size = root || matches!(sizes, Sizes::Exact) && !linked;
    if a.name != b.name
        || a.is_dir != b.is_dir
        || a.files != b.files
        || a.newest != b.newest
        || (check_size && a.size != b.size)
    {
        out.push(format!(
            "{path}: portable ({}, {} B, {} files, dir {}, newest {}) vs bulk ({}, {} B, {} files, dir {}, newest {})",
            a.name, a.size, a.files, a.is_dir, a.newest, b.name, b.size, b.files, b.is_dir, b.newest
        ));
    }
    let (ca, cb) = (by_name(a), by_name(b));
    if ca.len() != cb.len() {
        out.push(format!("{path}: {} children vs {}", ca.len(), cb.len()));
        return;
    }
    for (x, y) in ca.into_iter().zip(cb) {
        diff(x, y, &format!("{path}/{}", x.name), sizes, false, out);
    }
}

fn assert_equivalent(root: &Path, cross_fs: bool, sizes: Sizes) -> Node {
    let (portable, portable_errors) = scan(root, cross_fs, false);
    let (bulk, bulk_errors) = scan(root, cross_fs, true);
    let mut out = Vec::new();
    diff(&portable, &bulk, "", sizes, true, &mut out);
    assert!(
        out.is_empty(),
        "{} differences under {}:\n{}",
        out.len(),
        root.display(),
        out.iter().take(30).cloned().collect::<Vec<_>>().join("\n")
    );
    assert_eq!(
        portable_errors,
        bulk_errors,
        "errors under {}",
        root.display()
    );
    bulk
}

/// Files, nested folders, hard links, symlinks, empty and sparse files, compressed files,
/// a resource fork, special files and unicode names.
fn build_tree(r: &Path) {
    fs::write(r.join("small"), vec![1u8; 10_000]).unwrap();
    fs::write(r.join("empty"), b"").unwrap();
    fs::write(r.join("big"), vec![7u8; 3_000_000]).unwrap();

    let sparse = fs::File::create(r.join("sparse")).unwrap();
    sparse.set_len(1 << 30).unwrap();
    drop(sparse);
    let m = fs::metadata(r.join("sparse")).unwrap();
    assert!(m.blocks() * 512 < m.len(), "the sparse file is sparse");

    fs::write(r.join("linked-a"), vec![2u8; 200_000]).unwrap();
    fs::hard_link(r.join("linked-a"), r.join("linked-b")).unwrap();
    fs::hard_link(r.join("linked-a"), r.join("linked-c")).unwrap();

    std::os::unix::fs::symlink("small", r.join("link-to-file")).unwrap();
    std::os::unix::fs::symlink("deep", r.join("link-to-dir")).unwrap();
    std::os::unix::fs::symlink("nowhere/at/all", r.join("dangling")).unwrap();
    std::os::unix::fs::symlink("x".repeat(900), r.join("long-symlink")).unwrap();

    let deep = r.join("deep/a/b/c/d/e");
    fs::create_dir_all(&deep).unwrap();
    fs::write(deep.join("leaf"), vec![3u8; 50_000]).unwrap();
    fs::create_dir(r.join("empty-dir")).unwrap();

    for name in [
        "čćžšđ.txt",
        "日本語のファイル",
        "e\u{301}-decomposed",
        "\u{e9}-precomposed",
        "emoji-🌸🌼",
        "with space and 'quotes'",
    ] {
        fs::write(r.join(name), name.as_bytes()).unwrap();
    }
    fs::create_dir(r.join("папка")).unwrap();
    fs::write(r.join("папка/файл"), vec![4u8; 5_000]).unwrap();
    fs::write(r.join("n".repeat(255)), b"long name").unwrap();

    // Enough entries that one getattrlistbulk call cannot return them all.
    let many = r.join("many");
    fs::create_dir(&many).unwrap();
    for i in 0..3000 {
        fs::write(
            many.join(format!("file-with-a-longish-name-{i:05}")),
            vec![0u8; i % 7 * 1000],
        )
        .unwrap();
    }

    // A resource fork counts towards the allocated size.
    fs::write(r.join("forked"), b"data").unwrap();
    fs::write(r.join("forked/..namedfork/rsrc"), vec![5u8; 70_000]).unwrap();

    let _listener = std::os::unix::net::UnixListener::bind(r.join("socket")).unwrap();
    assert!(
        Command::new("mkfifo")
            .arg(r.join("fifo"))
            .status()
            .unwrap()
            .success()
    );

    // An APFS-compressed file: its allocation is far below its length.
    let plain = r.join("compressible-source");
    fs::write(&plain, "compress me ".repeat(100_000)).unwrap();
    let ok = Command::new("ditto")
        .arg("--hfsCompression")
        .arg(&plain)
        .arg(r.join("compressed"))
        .status()
        .is_ok_and(|s| s.success());
    assert!(ok, "ditto --hfsCompression");
    let m = fs::symlink_metadata(r.join("compressed")).unwrap();
    assert!(
        m.st_flags() & UF_COMPRESSED != 0,
        "compressed file is compressed"
    );
}

#[test]
fn bulk_matches_portable_on_a_test_tree() {
    let d = tempfile::tempdir().unwrap();
    build_tree(d.path());
    let node = assert_equivalent(d.path(), false, Sizes::Exact);

    let size = |name: &str| node.children.iter().find(|c| c.name == name).unwrap().size;
    assert!(
        size("sparse") < 1 << 20,
        "sparse file counted by allocation"
    );
    let m = fs::metadata(d.path().join("compressed")).unwrap();
    assert!(
        size("compressed") < m.len() / 4,
        "compressed file counted by allocation"
    );
    let linked: u64 = ["linked-a", "linked-b", "linked-c"].map(size).iter().sum();
    assert_eq!(
        linked,
        size("linked-a").max(size("linked-b")).max(size("linked-c"))
    );
    let many = node.children.iter().find(|c| c.name == "many").unwrap();
    assert_eq!(many.files, 3000);
}

#[test]
fn bulk_matches_portable_on_system_folders() {
    // The sealed system volume: compressed files, hard links, symlinks, unreadable parts.
    for root in [
        "/usr",
        "/System/Library/CoreServices",
        "/bin",
        "/private/etc",
    ] {
        assert_equivalent(Path::new(root), false, Sizes::RootOnly);
    }
}

#[test]
fn bulk_does_not_enter_other_volumes() {
    // Every folder here is the mount point of another APFS volume.
    let root = Path::new("/System/Volumes");
    let node = assert_equivalent(root, false, Sizes::Exact);
    let data = node.children.iter().find(|c| c.name == "Data").unwrap();
    assert!(data.children.is_empty(), "the Data volume is not entered");
}
