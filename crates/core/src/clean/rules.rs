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

/// How a [`HomeRule`] path is matched.
pub(super) enum Kind {
    /// Exactly this path.
    Exact,
    /// Every child of this folder is a separate candidate.
    Children,
    /// Children with one of these extensions (without the dot, any case).
    ChildrenExt(&'static [&'static str]),
}

/// Matches a known location relative to `$HOME`.
pub(super) struct HomeRule {
    pub path: &'static str,
    pub kind: Kind,
    pub category: Category,
}

const fn home(path: &'static str, kind: Kind, category: Category) -> HomeRule {
    HomeRule {
        path,
        kind,
        category,
    }
}

/// Exact rules win over `Children` rules: `Library/Caches/Homebrew` is a package
/// cache, every other child of `Library/Caches` is an app cache.
#[rustfmt::skip]
pub(super) const HOME_RULES: &[HomeRule] = &[
    // Xcode and iOS simulators
    home("Library/Developer/Xcode/DerivedData", Kind::Exact, XcodeDerived),
    home("Library/Developer/Xcode/iOS DeviceSupport", Kind::Children, XcodeDeviceSupport),
    home("Library/Developer/Xcode/watchOS DeviceSupport", Kind::Children, XcodeDeviceSupport),
    home("Library/Developer/Xcode/tvOS DeviceSupport", Kind::Children, XcodeDeviceSupport),
    home("Library/Developer/Xcode/visionOS DeviceSupport", Kind::Children, XcodeDeviceSupport),
    home("Library/Developer/Xcode/Archives", Kind::Children, XcodeArchives),
    home("Library/Developer/CoreSimulator/Devices", Kind::Children, Simulators),
    home("Library/Developer/CoreSimulator/Caches", Kind::Exact, SimulatorCache),
    home("Library/Caches/com.apple.dt.Xcode", Kind::Exact, XcodeDerived),
    // Android
    home(".android/avd", Kind::ChildrenExt(&["avd"]), AndroidEmulators),
    home("Library/Android/sdk/system-images", Kind::Children, AndroidImages),
    home(".android/cache", Kind::Exact, PkgCache),
    // Virtual machines
    home("Library/Containers/com.docker.docker/Data/vms", Kind::Exact, Vms),
    home("Library/Containers/com.utmapp.UTM/Data/Documents", Kind::ChildrenExt(&["utm"]), Vms),
    home("Parallels", Kind::ChildrenExt(&["pvm"]), Vms),
    home("Virtual Machines.localized", Kind::ChildrenExt(&["vmwarevm"]), Vms),
    // Package manager caches
    home("Library/Caches/Homebrew", Kind::Exact, PkgCache),
    home("Library/Caches/pip", Kind::Exact, PkgCache),
    home("Library/Caches/Yarn", Kind::Exact, PkgCache),
    home("Library/Caches/CocoaPods", Kind::Exact, PkgCache),
    home("Library/Caches/pnpm", Kind::Exact, PkgCache),
    home("Library/pnpm/store", Kind::Exact, PkgCache),
    home(".npm/_cacache", Kind::Exact, PkgCache),
    home(".cargo/registry/cache", Kind::Exact, PkgCache),
    home(".gradle/caches", Kind::Exact, PkgCache),
    home(".gradle/wrapper/dists", Kind::Exact, PkgCache),
    home(".m2/repository", Kind::Exact, PkgCache),
    home("go/pkg/mod", Kind::Exact, PkgCache),
    home(".nuget/packages", Kind::Exact, PkgCache),
    home(".bun/install/cache", Kind::Exact, PkgCache),
    // App caches and logs
    home("Library/Caches", Kind::Children, AppCache),
    home(".cache", Kind::Exact, AppCache),
    home("Library/Logs", Kind::Exact, Logs),
    // Worth a look before deleting
    home("Library/Application Support/MobileSync/Backup", Kind::Children, IosBackups),
    home("Downloads", Kind::ChildrenExt(&["dmg", "pkg", "iso", "xip"]), Installers),
    home(".Trash", Kind::Exact, Trash),
    home(".local/share/Trash", Kind::Exact, Trash),
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
