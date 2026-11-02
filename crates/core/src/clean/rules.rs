//! The rule tables. Adding a cleanup target usually means adding one line here.

#[allow(clippy::enum_glob_use)] // keeps the rule tables readable
use super::Category::{self, *};

/// Matches a folder by name anywhere on disk, with a condition on its neighbours.
pub(super) struct NameRule {
    /// `None` matches any name (the rule then relies on `child`).
    pub name: Option<&'static str>,
    /// At least one of these files must be next to the folder.
    pub sibling: &'static [&'static str],
    /// At least one of these files must be inside the folder.
    pub child: &'static [&'static str],
    pub category: Category,
}

const fn named(
    name: &'static str,
    sibling: &'static [&'static str],
    category: Category,
) -> NameRule {
    NameRule {
        name: Some(name),
        sibling,
        child: &[],
        category,
    }
}

const GRADLE_FILES: &[&str] = &[
    "build.gradle",
    "build.gradle.kts",
    "settings.gradle",
    "settings.gradle.kts",
];

pub(super) const NAME_RULES: &[NameRule] = &[
    named("target", &["Cargo.toml"], RustBuild),
    named("node_modules", &["package.json"], NodeDeps),
    named(".next", &["package.json"], JsBuild),
    named(".nuxt", &["package.json"], JsBuild),
    named(".turbo", &["package.json"], JsBuild),
    named("__pycache__", &[], PythonCache),
    named(".pytest_cache", &[], PythonCache),
    named(".mypy_cache", &[], PythonCache),
    named(".ruff_cache", &[], PythonCache),
    named(".gradle", GRADLE_FILES, Gradle),
    named("build", &["build.gradle", "build.gradle.kts"], Gradle),
    named("Pods", &["Podfile"], CocoaPods),
    named(".build", &["Package.swift"], SwiftBuild),
    // Python virtualenv: any folder with a pyvenv.cfg inside
    NameRule {
        name: None,
        sibling: &[],
        child: &["pyvenv.cfg"],
        category: PythonVenv,
    },
];

/// How a [`PathRule`] path is matched.
pub(super) enum Kind {
    /// Exactly this path.
    Exact,
    /// Every child of this folder is a separate candidate.
    Children,
    /// Children with one of these extensions (without the dot, any case).
    ChildrenExt(&'static [&'static str]),
    /// Child folders (not files) whose name starts with this prefix.
    ChildDirsPrefix(&'static str),
}

/// Matches a known location: relative to `$HOME` in [`HOME_RULES`], absolute in
/// [`SYSTEM_RULES`].
pub(super) struct PathRule {
    pub path: &'static str,
    pub kind: Kind,
    pub category: Category,
}

const fn at(path: &'static str, kind: Kind, category: Category) -> PathRule {
    PathRule {
        path,
        kind,
        category,
    }
}

/// Precedence, from strongest:
/// 1. `Exact` rules: `Library/Caches/Homebrew` is a package cache;
/// 2. a folder that has its own `Children` rule is never matched by its parent's:
///    `Library/Caches/JetBrains` is not one app cache, each IDE version in it is a
///    cache of one IDE version;
/// 3. the parent's `Children` rule: every other child of `Library/Caches` is an
///    app cache.
#[rustfmt::skip]
pub(super) const HOME_RULES: &[PathRule] = &[
    // Xcode and iOS simulators
    at("Library/Developer/Xcode/DerivedData", Kind::Exact, XcodeDerived),
    at("Library/Developer/Xcode/iOS DeviceSupport", Kind::Children, XcodeDeviceSupport),
    at("Library/Developer/Xcode/watchOS DeviceSupport", Kind::Children, XcodeDeviceSupport),
    at("Library/Developer/Xcode/tvOS DeviceSupport", Kind::Children, XcodeDeviceSupport),
    at("Library/Developer/Xcode/visionOS DeviceSupport", Kind::Children, XcodeDeviceSupport),
    at("Library/Developer/Xcode/Archives", Kind::Children, XcodeArchives),
    at("Library/Developer/CoreSimulator/Devices", Kind::Children, Simulators),
    at("Library/Developer/CoreSimulator/Caches", Kind::Exact, SimulatorCache),
    at("Library/Caches/com.apple.dt.Xcode", Kind::Exact, XcodeDerived),
    // Android
    at(".android/avd", Kind::ChildrenExt(&["avd"]), AndroidEmulators),
    at("Library/Android/sdk/system-images", Kind::Children, AndroidImages),
    at(".android/cache", Kind::Exact, PkgCache),
    // Virtual machines
    at("Library/Containers/com.docker.docker/Data/vms", Kind::Exact, Vms),
    at("Library/Containers/com.utmapp.UTM/Data/Documents", Kind::ChildrenExt(&["utm"]), Vms),
    at("Parallels", Kind::ChildrenExt(&["pvm"]), Vms),
    at("Virtual Machines.localized", Kind::ChildrenExt(&["vmwarevm"]), Vms),
    // Package manager caches
    at("Library/Caches/Homebrew", Kind::Exact, PkgCache),
    at("Library/Caches/pip", Kind::Exact, PkgCache),
    at("Library/Caches/Yarn", Kind::Exact, PkgCache),
    at("Library/Caches/CocoaPods", Kind::Exact, PkgCache),
    at("Library/Caches/pnpm", Kind::Exact, PkgCache),
    at("Library/pnpm/store", Kind::Exact, PkgCache),
    at(".npm/_cacache", Kind::Exact, PkgCache),
    at(".cargo/registry/cache", Kind::Exact, PkgCache),
    at(".gradle/caches", Kind::Exact, PkgCache),
    at(".gradle/wrapper/dists", Kind::Exact, PkgCache),
    at(".m2/repository", Kind::Exact, PkgCache),
    at("go/pkg/mod", Kind::Exact, PkgCache),
    at(".nuget/packages", Kind::Exact, PkgCache),
    at(".bun/install/cache", Kind::Exact, PkgCache),
    // App caches and logs
    // Node versions installed by nvm: v18.20.4, v20.11.0… Each one holds its global
    // packages in lib/node_modules; those go with the version, never on their own.
    at(".nvm/versions/node", Kind::ChildDirsPrefix("v"), NodeVersions),
    // JetBrains IDEs: <Product><version> per IDE, e.g. IntelliJIdea2025.2
    at("Library/Caches/JetBrains", Kind::Children, JetBrainsCache),
    at("Library/Logs/JetBrains", Kind::Children, JetBrainsCache),
    // VS Code and Cursor (Electron): only the caches and logs, never extensions,
    // User (settings, keybindings, snippets) or workspaceStorage.
    at("Library/Application Support/Code/Cache", Kind::Exact, EditorCache),
    at("Library/Application Support/Code/CachedData", Kind::Exact, EditorCache),
    at("Library/Application Support/Code/CachedExtensionVSIXs", Kind::Exact, EditorCache),
    at("Library/Application Support/Code/Code Cache", Kind::Exact, EditorCache),
    at("Library/Application Support/Code/GPUCache", Kind::Exact, EditorCache),
    at("Library/Application Support/Code/logs", Kind::Exact, EditorCache),
    at("Library/Application Support/Cursor/Cache", Kind::Exact, EditorCache),
    at("Library/Application Support/Cursor/CachedData", Kind::Exact, EditorCache),
    at("Library/Application Support/Cursor/Code Cache", Kind::Exact, EditorCache),
    at("Library/Application Support/Cursor/GPUCache", Kind::Exact, EditorCache),
    at("Library/Application Support/Cursor/logs", Kind::Exact, EditorCache),
    // App caches and logs
    at("Library/Caches", Kind::Children, AppCache),
    at(".cache", Kind::Exact, AppCache),
    // Each log folder on its own, so Library/Logs/JetBrains can have its own category.
    at("Library/Logs", Kind::Children, Logs),
    // Worth a look before deleting
    at("Library/Application Support/MobileSync/Backup", Kind::Children, IosBackups),
    at("Downloads", Kind::ChildrenExt(&["dmg", "pkg", "iso", "xip"]), Installers),
    at(".Trash", Kind::Exact, Trash),
    at(".local/share/Trash", Kind::Exact, Trash),
];

/// Absolute locations outside `$HOME`, matched like [`HOME_RULES`].
#[rustfmt::skip]
pub(super) const SYSTEM_RULES: &[PathRule] = &[
    // iOS / watchOS / tvOS / visionOS simulator runtimes downloaded by Xcode 15 and
    // later: Images/<uuid>.dmg (Xcode 15), Cryptex/Images/bundle/SimRuntimeBundle-<uuid>
    // (Xcode 16). CoreSimulator mounts them below Volumes, which is another volume and
    // not scanned. The app removes them with `xcrun simctl runtime delete`; the Inbox
    // folder and images.plist next to them are not matched.
    at("/Library/Developer/CoreSimulator/Images", Kind::ChildrenExt(&["dmg"]), SimRuntimes),
    at("/Library/Developer/CoreSimulator/Cryptex/Images/bundle", Kind::ChildDirsPrefix("SimRuntimeBundle-"), SimRuntimes),
];

/// Name rules (`node_modules`, `target`, `build`…) never apply below these: they hold
/// installed software, not projects (global npm packages, editor extensions,
/// toolchains). Home rules such as the caches in `~/Library/Caches` still apply.
pub(super) const PROTECTED_ABS: &[&str] = &[
    "/Applications",
    "/Library",
    "/System",
    "/usr",
    "/bin",
    "/sbin",
    "/opt/homebrew",
    "/opt/local",
    "/nix",
];

/// Same as [`PROTECTED_ABS`], relative to `$HOME`.
pub(super) const PROTECTED_HOME: &[&str] = &[
    "Library",
    "Applications",
    // Node version managers and global installs
    ".nvm",
    ".fnm",
    ".local/share/fnm",
    ".volta",
    ".asdf",
    ".npm",
    ".npm-global",
    ".pnpm-store",
    ".local/share/pnpm",
    ".bun",
    ".yarn",
    ".config/yarn",
    ".deno",
    ".node-gyp",
    // Editors and their extensions
    ".vscode",
    ".vscode-insiders",
    ".vscode-server",
    ".cursor",
    ".windsurf",
    ".zed",
    // Other toolchains
    ".cargo",
    ".rustup",
    ".gradle",
    ".m2",
    ".nuget",
    "go/pkg",
    ".sdkman",
    ".pyenv",
    ".rbenv",
    ".gem",
    ".conda",
    "miniconda3",
    "anaconda3",
    ".docker",
];
