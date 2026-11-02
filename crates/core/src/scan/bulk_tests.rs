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
    /// Like `Exact`, but the root and mounted volumes (`vol-*`) are compared without
    /// size and mtime: the system may write to a volume's root right after mounting.
    Mounts,
}

fn by_name(n: &Node) -> Vec<&Node> {
    let mut c: Vec<&Node> = n.children.iter().collect();
    c.sort_by(|x, y| x.name.cmp(&y.name));
    c
}

/// Collects every difference between `a` and `b`, children matched by name.
fn diff(a: &Node, b: &Node, path: &str, sizes: Sizes, root: bool, out: &mut Vec<String>) {
    let linked = !a.is_dir && a.name.starts_with("linked-");
    let loose = matches!(sizes, Sizes::Mounts) && (root || a.name.starts_with("vol-"));
    let check_size = !loose && (root || !matches!(sizes, Sizes::RootOnly) && !linked);
    if a.name != b.name
        || a.is_dir != b.is_dir
        || a.files != b.files
        || (!loose && a.newest != b.newest)
        || (check_size && a.size != b.size)
    {
        out.push(format!(
            "{path}: ({}, {} B, {} files, dir {}, newest {}) vs ({}, {} B, {} files, dir {}, newest {})",
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

/// For the benchmark: compares both paths on a live folder (`DISKBLOOM_EQUIV_ROOT`,
/// default `$HOME`), scanning portable, bulk, portable. Differences between the two
/// portable scans are changes made meanwhile by other processes, not the scanner.
#[test]
#[ignore = "diagnostic for a live folder, run by the benchmark workflow"]
fn bulk_matches_portable_on_a_live_folder() {
    let root = std::env::var_os("DISKBLOOM_EQUIV_ROOT")
        .or_else(|| std::env::var_os("HOME"))
        .map(PathBuf::from)
        .unwrap();
    let (first, first_errors) = scan(&root, false, false);
    let (bulk, bulk_errors) = scan(&root, false, true);
    let (second, second_errors) = scan(&root, false, false);
    let report = |label: &str, a: &Node, b: &Node| {
        let mut out = Vec::new();
        diff(a, b, "", Sizes::RootOnly, true, &mut out);
        println!("{label}: {} differences", out.len());
        for line in out.iter().take(15) {
            println!("  {line}");
        }
        out
    };
    println!(
        "files: portable {} / bulk {} / portable {}; errors {first_errors} / {bulk_errors} / {second_errors}",
        first.files, bulk.files, second.files
    );
    let churn = report("portable vs portable (other processes)", &first, &second);
    let before = report("portable vs bulk", &first, &bulk);
    let after = report("bulk vs portable", &bulk, &second);
    // A difference that is not churn shows up against both portable scans.
    let path = |l: &String| l.split(": ").next().unwrap_or_default().to_owned();
    let churned: HashSet<String> = churn.iter().map(path).collect();
    let after: HashSet<String> = after.iter().map(path).collect();
    let real: Vec<String> = before
        .iter()
        .map(path)
        .filter(|p| !churned.contains(p) && after.contains(p))
        .collect();
    assert!(
        real.is_empty(),
        "differences not explained by churn: {real:?}"
    );
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

fn run(cmd: &str, args: &[&OsStr]) {
    let status = Command::new(cmd).args(args).status().unwrap();
    assert!(status.success(), "{cmd} {args:?}");
}

/// A disk image mounted for a test; detached on drop.
struct Volume(PathBuf);

impl Volume {
    fn mount(images: &Path, at: &Path, fs_type: &str) -> Self {
        let image = images.join(format!("{}.dmg", at.file_name().unwrap().display()));
        let s = OsStr::new;
        run(
            "hdiutil",
            &[
                s("create"),
                s("-quiet"),
                s("-size"),
                s("20m"),
                s("-fs"),
                s(fs_type),
                s("-volname"),
                s("T"),
                image.as_os_str(),
            ],
        );
        fs::create_dir(at).unwrap();
        run(
            "hdiutil",
            &[
                s("attach"),
                s("-quiet"),
                s("-nobrowse"),
                s("-mountpoint"),
                at.as_os_str(),
                image.as_os_str(),
            ],
        );
        Self(at.to_path_buf())
    }
}

impl Drop for Volume {
    fn drop(&mut self) {
        let _ = Command::new("hdiutil")
            .args([
                OsStr::new("detach"),
                OsStr::new("-force"),
                self.0.as_os_str(),
            ])
            .status();
    }
}

#[test]
fn bulk_matches_portable_at_mount_points_and_on_other_file_systems() {
    let images = tempfile::tempdir().unwrap();
    let d = tempfile::tempdir().unwrap();
    fs::write(d.path().join("file"), vec![1u8; 20_000]).unwrap();
    let volumes = [
        ("vol-apfs", "APFS"),
        ("vol-hfs", "HFS+"),
        ("vol-fat", "MS-DOS"),
    ]
    .map(|(name, fs_type)| Volume::mount(images.path(), &d.path().join(name), fs_type));
    for vol in &volumes {
        let content = vol.0.join("content");
        fs::create_dir_all(content.join("sub/deeper")).unwrap();
        fs::write(content.join("a"), vec![2u8; 30_000]).unwrap();
        fs::write(content.join("sub/b"), vec![3u8; 70_000]).unwrap();
        fs::write(content.join("sub/deeper/c"), b"c").unwrap();
        fs::write(content.join("empty"), b"").unwrap();
        if !vol.0.ends_with("vol-fat") {
            fs::hard_link(content.join("a"), content.join("linked-a")).unwrap();
            fs::hard_link(content.join("a"), content.join("linked-b")).unwrap();
            std::os::unix::fs::symlink("sub", content.join("link")).unwrap();
            fs::write(content.join("ünïcödé"), b"u").unwrap();
        }
    }

    // Other volumes are not entered.
    let node = assert_equivalent(d.path(), false, Sizes::Mounts);
    for vol in &volumes {
        let name = vol.0.file_name().unwrap().to_string_lossy();
        let child = node.children.iter().find(|c| c.name == name).unwrap();
        assert!(
            child.is_dir && child.children.is_empty(),
            "{name} not entered"
        );
    }
    assert_eq!(node.files, 1);

    // Each file system read the same way (by bulk where it supports it).
    for vol in &volumes {
        let node = assert_equivalent(&vol.0.join("content"), false, Sizes::Exact);
        assert!(node.files >= 4, "{}", vol.0.display());
    }
}
