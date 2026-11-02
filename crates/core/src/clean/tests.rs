#![allow(clippy::many_single_char_names)]

use super::*;
use crate::scan::Scanner;
use std::fs;

#[test]
fn rules_cover_projects_emulators_caches() {
    let d = tempfile::tempdir().unwrap();
    let r = fs::canonicalize(d.path()).unwrap();
    let w = |p: &str| {
        let p = r.join(p);
        fs::create_dir_all(p.parent().unwrap()).unwrap();
        fs::write(p, vec![7u8; 9000]).unwrap();
    };
    // projects
    w("rs/Cargo.toml");
    w("rs/target/debug/app");
    w("notrust/target/keep");
    w("js/package.json");
    w("js/node_modules/x/i.js");
    w("py/__pycache__/m.pyc");
    w("py/.venv/pyvenv.cfg");
    w("py/.venv/lib/site/__pycache__/x.pyc"); // covered by the venv, not listed separately
    w("h/.DS_Store"); // no longer reported
    // home rules
    w("h/Library/Caches/com.app.one/blob");
    w("h/Library/Caches/Homebrew/bottle.tar.gz");
    w("h/Library/Developer/CoreSimulator/Devices/AAAA-1111/data/x");
    w("h/Library/Developer/CoreSimulator/Devices/BBBB-2222/data/x");
    w("h/Library/Developer/Xcode/DerivedData/App-abc/Build/x");
    w("h/.android/avd/Pixel_8.avd/userdata.img");
    w("h/.android/avd/Pixel_8.ini");
    w("h/Downloads/Installer.dmg");
    w("h/Downloads/photo.jpg");

    let s = Scanner::new(&r, false).unwrap();
    let tree = Tree::from_node(s.scan().unwrap(), r.clone());
    let c = find_with_home(&tree, Some(&r.join("h")));
    let mut got: Vec<_> = c
        .iter()
        .map(|c| {
            (
                c.path
                    .strip_prefix(&r)
                    .unwrap()
                    .to_string_lossy()
                    .into_owned(),
                c.category.id(),
                c.is_safe(),
            )
        })
        .collect();
    got.sort();
    let want: Vec<(String, &str, bool)> = vec![
        (
            "h/.android/avd/Pixel_8.avd".into(),
            "android-emulators",
            false,
        ),
        ("h/Downloads/Installer.dmg".into(), "installers", false),
        ("h/Library/Caches/Homebrew".into(), "pkg-cache", true),
        ("h/Library/Caches/com.app.one".into(), "app-cache", true),
        (
            "h/Library/Developer/CoreSimulator/Devices/AAAA-1111".into(),
            "simulators",
            false,
        ),
        (
            "h/Library/Developer/CoreSimulator/Devices/BBBB-2222".into(),
            "simulators",
            false,
        ),
        (
            "h/Library/Developer/Xcode/DerivedData".into(),
            "xcode-derived",
            true,
        ),
        ("js/node_modules".into(), "node-deps", true),
        ("py/.venv".into(), "python-venv", false),
        ("py/__pycache__".into(), "python-cache", true),
        ("rs/target".into(), "rust-build", true),
    ];
    assert_eq!(got, want);
    for c in &c {
        assert_eq!(tree.find(&c.path), Some(c.id));
    }
}

#[test]
fn global_and_tool_node_modules_are_never_flagged() {
    let d = tempfile::tempdir().unwrap();
    let r = fs::canonicalize(d.path()).unwrap();
    let w = |p: &str| {
        let p = r.join(p);
        fs::create_dir_all(p.parent().unwrap()).unwrap();
        fs::write(p, vec![7u8; 9000]).unwrap();
    };
    // a real project: its node_modules is a candidate (only that one, not nested ones)
    w("h/code/app/package.json");
    w("h/code/app/node_modules/dep/package.json");
    w("h/code/app/node_modules/dep/node_modules/sub/i.js");
    // global npm via nvm: lib/node_modules/<package>/{package.json,node_modules}
    w("h/.nvm/versions/node/v20/lib/node_modules/npm/package.json");
    w("h/.nvm/versions/node/v20/lib/node_modules/npm/node_modules/x/i.js");
    // npm global prefix outside a version manager: still inside node_modules
    w("h/npm-prefix/lib/node_modules/@angular/cli/package.json");
    w("h/npm-prefix/lib/node_modules/@angular/cli/node_modules/y/i.js");
    // pnpm / bun / yarn global: package.json + node_modules, but protected
    w("h/Library/pnpm/global/5/package.json");
    w("h/Library/pnpm/global/5/node_modules/z/i.js");
    w("h/.bun/install/global/package.json");
    w("h/.bun/install/global/node_modules/z/i.js");
    w("h/.config/yarn/global/package.json");
    w("h/.config/yarn/global/node_modules/z/i.js");
    // editor extension
    w("h/.vscode/extensions/ext.one/package.json");
    w("h/.vscode/extensions/ext.one/node_modules/q/i.js");
    // Electron app
    w("apps/Some.app/Contents/Resources/app/package.json");
    w("apps/Some.app/Contents/Resources/app/node_modules/e/i.js");
    // a user folder that happens to be called DerivedData (not Xcode's)
    w("h/data/DerivedData/results.csv");
    // Rust toolchain in ~/.cargo: target/ next to Cargo.toml in a git checkout
    w("h/.cargo/git/checkouts/crate/Cargo.toml");
    w("h/.cargo/git/checkouts/crate/target/x");

    let s = Scanner::new(&r, false).unwrap();
    let tree = Tree::from_node(s.scan().unwrap(), r.clone());
    let c = find_with_home(&tree, Some(&r.join("h")));
    let mut got: Vec<_> = c
        .iter()
        .map(|c| {
            let path = c.path.strip_prefix(&r).unwrap().to_string_lossy();
            (path.into_owned(), c.category.id(), c.is_safe())
        })
        .collect();
    got.sort();
    // The nvm version is offered as a whole (review, never preselected); its global
    // packages are never offered on their own.
    let want = vec![
        row("h/.nvm/versions/node/v20", "node-versions", false),
        row("h/code/app/node_modules", "node-deps", true),
    ];
    assert_eq!(got, want);
}

#[test]
fn home_rules_match_boot_volume_paths() {
    // Boot disk scan: tree paths start with /System/Volumes/Data,
    // while $HOME is /Users/x. Home rules must still match.
    let rules = Rules::new(Some(Path::new("/Users/x")), Path::new("/"));
    assert!(
        rules
            .children
            .contains_key(Path::new("/System/Volumes/Data/Users/x/Library/Logs"))
    );
    assert!(
        rules
            .children
            .contains_key(Path::new("/Users/x/Library/Logs"))
    );
    assert!(rules.exact.contains_key(Path::new(
        "/System/Volumes/Data/Users/x/Library/Application Support/Code/CachedData"
    )));
    // System rules are absolute and also registered in both forms.
    for images in [
        "/Library/Developer/CoreSimulator/Images",
        "/System/Volumes/Data/Library/Developer/CoreSimulator/Images",
    ] {
        assert!(rules.children.contains_key(Path::new(images)), "{images}");
    }
    assert!(
        rules
            .children
            .contains_key(Path::new("/System/Volumes/Data/Users/x/Library/Caches"))
    );
    assert!(
        rules
            .protected
            .contains(Path::new("/System/Volumes/Data/Users/x/.nvm"))
    );
    assert!(
        rules
            .protected
            .contains(Path::new("/System/Volumes/Data/Applications"))
    );
}

#[test]
fn scanning_inside_rule_folder_lists_children() {
    // Scanning ~/Library/Caches itself: every child is a candidate.
    let d = tempfile::tempdir().unwrap();
    let r = fs::canonicalize(d.path()).unwrap();
    let caches = r.join("Library/Caches");
    fs::create_dir_all(caches.join("a")).unwrap();
    fs::write(caches.join("a/f"), vec![1u8; 9000]).unwrap();
    let s = Scanner::new(&caches, false).unwrap();
    let tree = Tree::from_node(s.scan().unwrap(), caches.clone());
    let c = find_with_home(&tree, Some(&r));
    assert_eq!(c.len(), 1);
    assert_eq!(c[0].category, Category::AppCache);
}

/// Writes each path (relative to `root`) as a 9000-byte file.
fn write_files<S: AsRef<str>>(root: &Path, paths: &[S]) {
    for p in paths {
        let p = root.join(p.as_ref());
        fs::create_dir_all(p.parent().unwrap()).unwrap();
        fs::write(p, vec![7u8; 9000]).unwrap();
    }
}

/// Scans `root` with `root/h` as home and `root/sys` in place of `/` for the system
/// rules. Returns (path relative to `root`, category id, safe), sorted.
fn found(root: &Path) -> Vec<(String, &'static str, bool)> {
    let s = Scanner::new(root, false).unwrap();
    let tree = Tree::from_node(s.scan().unwrap(), root.to_path_buf());
    let mut got: Vec<_> = find_with_roots(&tree, Some(&root.join("h")), &root.join("sys"))
        .iter()
        .map(|c| {
            assert_eq!(tree.find(&c.path), Some(c.id));
            let path = c.path.strip_prefix(root).unwrap().to_string_lossy();
            (path.into_owned(), c.category.id(), c.is_safe())
        })
        .collect();
    got.sort();
    got
}

fn temp_root() -> (tempfile::TempDir, PathBuf) {
    let d = tempfile::tempdir().unwrap();
    let r = fs::canonicalize(d.path()).unwrap();
    (d, r)
}

fn row(path: &str, id: &'static str, safe: bool) -> (String, &'static str, bool) {
    (path.to_string(), id, safe)
}

#[test]
fn jetbrains_caches_and_logs_win_over_app_cache_and_logs() {
    let (_d, r) = temp_root();
    write_files(
        &r,
        &[
            "h/Library/Caches/JetBrains/IntelliJIdea2025.2/caches/x",
            "h/Library/Caches/JetBrains/PyCharm2025.1/index/x",
            "h/Library/Logs/JetBrains/IntelliJIdea2025.2/idea.log",
            // other caches and logs keep their generic category
            "h/Library/Caches/com.app.one/blob",
            "h/Library/Caches/IntelliJIdea2019.3/x", // pre-2020 layout: an app cache
            "h/Library/Logs/DiagnosticReports/a.ips",
            // settings and plugins are not caches
            "h/Library/Application Support/JetBrains/IntelliJIdea2025.2/options/x.xml",
            "h/Library/Application Support/JetBrains/IntelliJIdea2025.2/plugins/p.jar",
            // lookalikes outside ~/Library
            "h/code/JetBrains/IntelliJIdea2025.2/x",
            "h/Caches/JetBrains/IntelliJIdea2025.2/x",
            "h/Logs/JetBrains/IntelliJIdea2025.2/x",
        ],
    );
    let want = vec![
        row("h/Library/Caches/IntelliJIdea2019.3", "app-cache", true),
        row(
            "h/Library/Caches/JetBrains/IntelliJIdea2025.2",
            "jetbrains-cache",
            true,
        ),
        row(
            "h/Library/Caches/JetBrains/PyCharm2025.1",
            "jetbrains-cache",
            true,
        ),
        row("h/Library/Caches/com.app.one", "app-cache", true),
        row("h/Library/Logs/DiagnosticReports", "logs", true),
        row(
            "h/Library/Logs/JetBrains/IntelliJIdea2025.2",
            "jetbrains-cache",
            true,
        ),
    ];
    assert_eq!(found(&r), want);
}

#[test]
fn editor_caches_never_include_extensions_or_settings() {
    let (_d, r) = temp_root();
    let code = "h/Library/Application Support/Code";
    let cursor = "h/Library/Application Support/Cursor";
    let code_caches = [
        "Cache",
        "CachedData",
        "CachedExtensionVSIXs",
        "Code Cache",
        "GPUCache",
        "logs",
    ];
    let cursor_caches = ["Cache", "CachedData", "Code Cache", "GPUCache", "logs"];
    let mut files: Vec<String> = code_caches
        .iter()
        .map(|c| format!("{code}/{c}/f"))
        .chain(cursor_caches.iter().map(|c| format!("{cursor}/{c}/f")))
        .collect();
    for keep in [
        "User/settings.json",
        "User/keybindings.json",
        "User/workspaceStorage/0a1b/state.vscdb",
        "User/globalStorage/state.vscdb",
        "User/History/x",
        "User/Cache/x", // a cache name deeper down is not the editor's cache
        "Backups/x",
        "Local Storage/leveldb/x",
    ] {
        files.push(format!("{code}/{keep}"));
        files.push(format!("{cursor}/{keep}"));
    }
    files.extend(
        [
            "h/.vscode/extensions/ms-python.python/x",
            "h/.cursor/extensions/ext/x",
            // lookalikes
            "h/projects/Code/Cache/x",
            "h/Library/Application Support/Other/Cache/x",
            "h/Library/Application Support/Code - Backup/Cache/x",
        ]
        .map(String::from),
    );
    write_files(&r, &files);

    let mut want: Vec<_> = code_caches
        .iter()
        .map(|c| row(&format!("{code}/{c}"), "editor-cache", true))
        .chain(
            cursor_caches
                .iter()
                .map(|c| row(&format!("{cursor}/{c}"), "editor-cache", true)),
        )
        .collect();
    want.sort();
    assert_eq!(found(&r), want);
}

#[test]
fn nvm_versions_need_review_and_their_global_packages_are_not_separate() {
    let (_d, r) = temp_root();
    write_files(
        &r,
        &[
            "h/.nvm/versions/node/v18.20.4/bin/node",
            "h/.nvm/versions/node/v18.20.4/lib/node_modules/npm/package.json",
            "h/.nvm/versions/node/v18.20.4/lib/node_modules/npm/node_modules/x/i.js",
            "h/.nvm/versions/node/v20.11.0/bin/node",
            "h/.nvm/versions/node/v20.11.0/lib/package.json",
            "h/.nvm/versions/node/v20.11.0/lib/node_modules/typescript/package.json",
            "h/.nvm/versions/node/.DS_Store", // a file, not a version
            "h/.nvm/versions/node/current/x", // not a version folder
            "h/.nvm/nvm.sh",
            "h/.nvm/alias/default",
            "h/.nvm/.cache/bin/node-v20.11.0/node.tar.xz",
            // lookalikes outside ~/.nvm
            "h/code/.nvm/versions/node/v1.0.0/bin/node",
            "h/other/versions/node/v20.11.0/bin/node",
        ],
    );
    let want = vec![
        row("h/.nvm/versions/node/v18.20.4", "node-versions", false),
        row("h/.nvm/versions/node/v20.11.0", "node-versions", false),
    ];
    assert_eq!(found(&r), want);
}

#[test]
fn sim_runtimes_are_only_the_runtime_images() {
    let (_d, r) = temp_root();
    let sim = "sys/Library/Developer/CoreSimulator";
    let xcode15 = "Images/EB213AC6-D0C7-494C-B960-A0888D020599.dmg";
    let xcode16 = "Cryptex/Images/bundle/SimRuntimeBundle-81A82E90-ACDD-47C8-A3B1-A93E7FC76A93";
    let mut files: Vec<String> = [
        xcode15,
        "Images/images.plist",
        "Images/Inbox/partial.dmg",
        &format!("{xcode16}/Restore/043-19278-100.dmg"),
        "Cryptex/Images/bundle/SimRuntimeBundle-file", // a file, not a bundle
        "Cryptex/Images/bundle/other/x.dmg",
        // where runtimes are mounted (another volume on a real Mac)
        "Volumes/iOS_22A3351/x",
        "Caches/x",
    ]
    .iter()
    .map(|f| format!("{sim}/{f}"))
    .collect();
    files.extend(
        [
            // the same layout inside a home folder is not a runtime
            "h/Library/Developer/CoreSimulator/Images/EB213AC6-D0C7-494C-B960-A0888D020599.dmg",
            "sys/Users/x/Library/Developer/CoreSimulator/Images/A.dmg",
            "h/Downloads/iOS_18.dmg",
        ]
        .map(String::from),
    );
    write_files(&r, &files);
    let want = vec![
        row("h/Downloads/iOS_18.dmg", "installers", false),
        row(&format!("{sim}/{xcode16}"), "sim-runtimes", false),
        row(&format!("{sim}/{xcode15}"), "sim-runtimes", false),
    ];
    assert_eq!(found(&r), want);
}

#[test]
fn delete_refuses_categories_that_need_their_tool() {
    let (_d, r) = temp_root();
    write_files(&r, &["runtime.dmg"]);
    let c = Candidate {
        id: 0,
        path: r.join("runtime.dmg"),
        size: 9000,
        category: Category::SimRuntimes,
        is_dir: false,
    };
    assert!(delete(&c).is_err());
    assert!(r.join("runtime.dmg").exists());
}
