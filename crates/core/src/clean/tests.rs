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
    let got: Vec<_> = c
        .iter()
        .map(|c| {
            c.path
                .strip_prefix(&r)
                .unwrap()
                .to_string_lossy()
                .into_owned()
        })
        .collect();
    assert_eq!(got, vec!["h/code/app/node_modules".to_string()]);
}

#[test]
fn home_rules_match_boot_volume_paths() {
    // Boot disk scan: tree paths start with /System/Volumes/Data,
    // while $HOME is /Users/x. Home rules must still match.
    let rules = Rules::new(Some(Path::new("/Users/x")));
    assert!(
        rules
            .exact
            .contains_key(Path::new("/System/Volumes/Data/Users/x/Library/Logs"))
    );
    assert!(rules.exact.contains_key(Path::new("/Users/x/Library/Logs")));
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
