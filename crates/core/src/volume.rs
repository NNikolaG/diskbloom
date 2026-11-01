//! macOS boot volume paths.
//!
//! Since Catalina the boot disk is split into a read-only system volume (`/`) and a
//! data volume mounted at `/System/Volumes/Data`. Folders such as `/Users` exist on
//! both through "firmlinks". The scanner never crosses volumes, so the app scans the
//! data volume directly, and every path it reports starts with [`DATA_VOLUME`].
//!
//! The rest of the system (Finder, the Trash, `$HOME`) uses the short form
//! (`/Users/me`), so paths must be converted in both directions.

use std::path::{Path, PathBuf};

/// Mount point of the boot data volume on macOS.
pub const DATA_VOLUME: &str = "/System/Volumes/Data";

/// `/System/Volumes/Data/Users/me` → `/Users/me`; [`DATA_VOLUME`] itself → `/`.
/// Returns `None` for paths outside the data volume.
pub fn strip_data_volume(path: &Path) -> Option<PathBuf> {
    path.strip_prefix(DATA_VOLUME)
        .ok()
        .map(|rest| Path::new("/").join(rest))
}

/// `/Users/me` → `/System/Volumes/Data/Users/me`.
pub fn on_data_volume(path: &Path) -> PathBuf {
    Path::new(DATA_VOLUME).join(path.strip_prefix("/").unwrap_or(path))
}

/// The path in both forms, so a rule matches whichever form a scan produced.
pub fn both_forms(path: PathBuf) -> [PathBuf; 2] {
    let data = on_data_volume(&path);
    [path, data]
}

/// The short (firmlinked) form of a data-volume path, if `exists` confirms it.
///
/// macOS refuses to move items under `/System/Volumes/Data/...` to the user's Trash
/// ("You do not have permission"), while the same item reached through `/Users/...`
/// works. The volume root itself and paths that are not firmlinked stay unchanged.
pub fn firmlinked(path: &Path, exists: impl Fn(&Path) -> bool) -> PathBuf {
    match strip_data_volume(path) {
        Some(short) if short != Path::new("/") && exists(&short) => short,
        _ => path.to_path_buf(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strip_and_add_are_inverse() {
        let long = Path::new("/System/Volumes/Data/Users/n/x");
        let short = strip_data_volume(long).unwrap();
        assert_eq!(short, Path::new("/Users/n/x"));
        assert_eq!(on_data_volume(&short), long);
        assert_eq!(
            strip_data_volume(Path::new(DATA_VOLUME)).unwrap(),
            Path::new("/")
        );
        assert_eq!(strip_data_volume(Path::new("/Volumes/USB")), None);
    }

    #[test]
    fn firmlinked_uses_short_form_only_when_it_exists() {
        let p = Path::new("/System/Volumes/Data/Users/n/projects/x/node_modules");
        assert_eq!(
            firmlinked(p, |_| true),
            Path::new("/Users/n/projects/x/node_modules")
        );
        assert_eq!(firmlinked(p, |_| false), p);
        assert_eq!(
            firmlinked(Path::new(DATA_VOLUME), |_| true),
            Path::new(DATA_VOLUME)
        );
        assert_eq!(
            firmlinked(Path::new("/Volumes/USB/a"), |_| true),
            Path::new("/Volumes/USB/a")
        );
    }
}
