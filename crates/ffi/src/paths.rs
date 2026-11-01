use diskbloom_core::volume;
use std::path::Path;

/// The path to hand to the app for Trash, Finder and Quick Look: the firmlinked
/// `/Users/...` form when the scan went through `/System/Volumes/Data`.
pub fn user_path(path: &Path) -> String {
    volume::firmlinked(path, Path::exists)
        .to_string_lossy()
        .into_owned()
}
