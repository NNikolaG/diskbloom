use std::fmt;

/// What a cleanup candidate is. The [`Category::id`] strings are stable: the CLI
/// accepts them and the app uses them for icons, translations and special handling.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
#[allow(missing_docs)] // the names say it; see `Category::id` and the README table
pub enum Category {
    RustBuild,
    NodeDeps,
    JsBuild,
    PythonCache,
    PythonVenv,
    Gradle,
    CocoaPods,
    SwiftBuild,
    XcodeDerived,
    XcodeDeviceSupport,
    XcodeArchives,
    Simulators,
    SimulatorCache,
    AndroidEmulators,
    AndroidImages,
    Vms,
    PkgCache,
    AppCache,
    Logs,
    IosBackups,
    Installers,
    Trash,
}

impl Category {
    /// Every category, in display order.
    pub const ALL: [Category; 22] = [
        Self::RustBuild,
        Self::NodeDeps,
        Self::JsBuild,
        Self::PythonCache,
        Self::PythonVenv,
        Self::Gradle,
        Self::CocoaPods,
        Self::SwiftBuild,
        Self::XcodeDerived,
        Self::XcodeDeviceSupport,
        Self::XcodeArchives,
        Self::Simulators,
        Self::SimulatorCache,
        Self::AndroidEmulators,
        Self::AndroidImages,
        Self::Vms,
        Self::PkgCache,
        Self::AppCache,
        Self::Logs,
        Self::IosBackups,
        Self::Installers,
        Self::Trash,
    ];

    /// Stable kebab-case identifier, e.g. `rust-build`.
    pub const fn id(self) -> &'static str {
        match self {
            Self::RustBuild => "rust-build",
            Self::NodeDeps => "node-deps",
            Self::JsBuild => "js-build",
            Self::PythonCache => "python-cache",
            Self::PythonVenv => "python-venv",
            Self::Gradle => "gradle",
            Self::CocoaPods => "cocoapods",
            Self::SwiftBuild => "swift-build",
            Self::XcodeDerived => "xcode-derived",
            Self::XcodeDeviceSupport => "xcode-device-support",
            Self::XcodeArchives => "xcode-archives",
            Self::Simulators => "simulators",
            Self::SimulatorCache => "simulator-cache",
            Self::AndroidEmulators => "android-emulators",
            Self::AndroidImages => "android-images",
            Self::Vms => "vms",
            Self::PkgCache => "pkg-cache",
            Self::AppCache => "app-cache",
            Self::Logs => "logs",
            Self::IosBackups => "ios-backups",
            Self::Installers => "installers",
            Self::Trash => "trash",
        }
    }

    /// Parses an [`Category::id`].
    pub fn from_id(id: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|c| c.id() == id)
    }

    /// Build output and dependencies inside a project folder. For these, how long ago
    /// the project itself was changed tells whether it is still in use.
    pub const fn is_project(self) -> bool {
        matches!(
            self,
            Self::RustBuild
                | Self::NodeDeps
                | Self::JsBuild
                | Self::PythonCache
                | Self::PythonVenv
                | Self::Gradle
                | Self::CocoaPods
                | Self::SwiftBuild
        )
    }

    /// Safe categories regenerate on their own (builds, caches) and may be removed
    /// without looking. The others (emulators, VMs, backups, installers) need review.
    pub const fn is_safe(self) -> bool {
        !matches!(
            self,
            Self::PythonVenv
                | Self::XcodeArchives
                | Self::Simulators
                | Self::AndroidEmulators
                | Self::AndroidImages
                | Self::Vms
                | Self::IosBackups
                | Self::Installers
                | Self::Trash
        )
    }
}

impl fmt::Display for Category {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.id())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_round_trip_and_are_unique() {
        for c in Category::ALL {
            assert_eq!(Category::from_id(c.id()), Some(c));
        }
        let mut ids: Vec<_> = Category::ALL.iter().map(|c| c.id()).collect();
        ids.sort_unstable();
        ids.dedup();
        assert_eq!(ids.len(), Category::ALL.len());
        assert_eq!(Category::from_id("nope"), None);
    }
}
