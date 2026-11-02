//! File types: what the scanned space is made of (video, images, apps, …).
//!
//! Files are classified by extension, ignoring case. A few folders are packages that
//! macOS shows as one file, such as `.app` bundles: they count as one item with their
//! full size and are not looked into.

use crate::tree::{Entry, NodeId, Tree};
use std::cmp::Reverse;
use std::collections::BinaryHeap;

/// A broad kind of file.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Kind {
    /// Movies and screen recordings.
    Video,
    /// Photos, pictures and design files.
    Images,
    /// Music, podcasts and recordings.
    Audio,
    /// Compressed archives, installers and disk images.
    Archives,
    /// Office documents, PDFs, e-books and text.
    Documents,
    /// Source code, project files and build output.
    Code,
    /// `.app` bundles.
    Apps,
    /// Libraries, frameworks, settings and databases.
    System,
    /// Everything else, including files without an extension.
    Other,
}

impl Kind {
    /// Every kind, in display order.
    pub const ALL: [Kind; 9] = [
        Kind::Video,
        Kind::Images,
        Kind::Audio,
        Kind::Archives,
        Kind::Documents,
        Kind::Code,
        Kind::Apps,
        Kind::System,
        Kind::Other,
    ];

    /// Stable id, e.g. `video`, for the CLI and the app.
    pub fn id(self) -> &'static str {
        match self {
            Kind::Video => "video",
            Kind::Images => "images",
            Kind::Audio => "audio",
            Kind::Archives => "archives",
            Kind::Documents => "documents",
            Kind::Code => "code",
            Kind::Apps => "apps",
            Kind::System => "system",
            Kind::Other => "other",
        }
    }

    /// The kind of a file, from the extension of its name.
    pub fn of_file(name: &str) -> Kind {
        let mut buf = [0u8; MAX_EXT];
        extension(name, &mut buf).map_or(Kind::Other, file_kind)
    }

    /// The kind of a folder that is a package counted as one item (an `.app` bundle,
    /// a sparse bundle, a Pages document, …), or `None` for an ordinary folder.
    pub fn of_package(name: &str) -> Option<Kind> {
        let mut buf = [0u8; MAX_EXT];
        extension(name, &mut buf).and_then(package_kind)
    }

    fn index(self) -> usize {
        self as usize
    }
}

/// Total size and number of items of one kind.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KindTotal {
    /// The kind.
    pub kind: Kind,
    /// Allocated size in bytes.
    pub size: u64,
    /// Number of items: files, plus packages counted once each.
    pub count: u64,
}

impl Tree {
    /// Size and count per kind, for every kind in [`Kind::ALL`] order (including empty
    /// ones). One pass over the tree.
    pub fn kind_totals(&self) -> Vec<KindTotal> {
        let mut totals = Kind::ALL.map(|kind| KindTotal {
            kind,
            size: 0,
            count: 0,
        });
        let mut walk = ItemWalk::new(self);
        while let Some((kind, _, e)) = walk.next(0) {
            let t = &mut totals[kind.index()];
            t.size += e.size;
            t.count += 1;
        }
        totals.to_vec()
    }

    /// The `limit` largest items of `kind`, largest first. Folders that cannot hold
    /// anything larger than what was already found are skipped.
    pub fn largest_of_kind(&self, kind: Kind, limit: usize) -> Vec<NodeId> {
        if limit == 0 {
            return Vec::new();
        }
        let mut heap = BinaryHeap::with_capacity(limit + 1);
        let mut walk = ItemWalk::new(self);
        let mut floor = 0;
        while let Some((k, id, e)) = walk.next(floor) {
            if k != kind {
                continue;
            }
            heap.push(Reverse((e.size, id)));
            if heap.len() > limit {
                heap.pop();
            }
            if heap.len() == limit {
                floor = heap.peek().map_or(0, |Reverse((size, _))| *size + 1);
            }
        }
        heap.into_sorted_vec()
            .into_iter()
            .map(|Reverse((_, id))| id)
            .collect()
    }
}

/// Depth-first walk over the items of a tree: files, and packages as a whole.
struct ItemWalk<'a> {
    tree: &'a Tree,
    stack: Vec<NodeId>,
}

impl<'a> ItemWalk<'a> {
    fn new(tree: &'a Tree) -> Self {
        Self {
            tree,
            stack: vec![tree.root()],
        }
    }

    /// The next item; entries smaller than `floor` are skipped with everything below them.
    fn next(&mut self, floor: u64) -> Option<(Kind, NodeId, &'a Entry)> {
        while let Some(id) = self.stack.pop() {
            let Some(e) = self.tree.get(id) else { continue };
            if e.size < floor {
                continue;
            }
            if !e.is_dir {
                return Some((Kind::of_file(&e.name), id, e));
            }
            if let Some(kind) = Kind::of_package(&e.name) {
                return Some((kind, id, e));
            }
            self.stack.extend_from_slice(&e.children);
        }
        None
    }
}

/// Longest extension looked at; longer ones are not in any table.
const MAX_EXT: usize = 16;

/// The lowercased extension of `name` in `buf`: after the last dot, not for names that
/// start with their only dot (`.DS_Store`). `None` if empty, too long or not ASCII.
fn extension<'b>(name: &str, buf: &'b mut [u8; MAX_EXT]) -> Option<&'b str> {
    let (stem, ext) = name.rsplit_once('.')?;
    if stem.is_empty() || ext.is_empty() || ext.len() > MAX_EXT || !ext.is_ascii() {
        return None;
    }
    let out = &mut buf[..ext.len()];
    out.copy_from_slice(ext.as_bytes());
    out.make_ascii_lowercase();
    std::str::from_utf8(out).ok()
}

fn package_kind(ext: &str) -> Option<Kind> {
    Some(match ext {
        "app" => Kind::Apps,
        "sparsebundle" | "sparseimage" => Kind::Archives,
        "pages" | "numbers" | "key" | "rtfd" => Kind::Documents,
        "framework" | "bundle" | "plugin" | "kext" | "dsym" | "xpc" | "appex" | "prefpane"
        | "qlgenerator" | "mdimporter" | "component" | "vst" | "vst3" => Kind::System,
        _ => return None,
    })
}

fn file_kind(ext: &str) -> Kind {
    match ext {
        "mp4" | "m4v" | "mov" | "avi" | "mkv" | "wmv" | "flv" | "webm" | "mpg" | "mpeg" | "m2v"
        | "3gp" | "3g2" | "mts" | "m2ts" | "vob" | "ogv" | "asf" | "rm" | "rmvb" | "divx"
        | "f4v" | "mxf" | "braw" | "r3d" | "insv" | "hevc" | "264" | "265" => Kind::Video,
        "jpg" | "jpeg" | "jpe" | "png" | "gif" | "heic" | "heif" | "webp" | "avif" | "jxl"
        | "tif" | "tiff" | "bmp" | "svg" | "ico" | "icns" | "psd" | "psb" | "ai" | "eps"
        | "raw" | "dng" | "cr2" | "cr3" | "crw" | "nef" | "nrw" | "arw" | "srf" | "sr2" | "orf"
        | "rw2" | "raf" | "pef" | "srw" | "x3f" | "exr" | "hdr" | "xcf" | "sketch" | "fig"
        | "afphoto" | "afdesign" | "pxd" | "kra" | "procreate" => Kind::Images,
        "mp3" | "m4a" | "m4b" | "m4r" | "m4p" | "aac" | "wav" | "aif" | "aiff" | "aifc"
        | "flac" | "alac" | "ogg" | "oga" | "opus" | "wma" | "mid" | "midi" | "caf" | "amr"
        | "ape" | "wv" | "dsf" | "dff" | "au" | "snd" | "band" | "logicx" => Kind::Audio,
        "zip" | "rar" | "7z" | "tar" | "gz" | "tgz" | "bz2" | "tbz" | "tbz2" | "xz" | "txz"
        | "zst" | "lz" | "lz4" | "lzma" | "z" | "cab" | "arj" | "sit" | "sitx" | "xar" | "cpio"
        | "dmg" | "iso" | "img" | "toast" | "cdr" | "pkg" | "mpkg" | "xip" | "ipa" | "apk"
        | "aab" | "xapk" | "vmdk" | "vdi" | "vhd" | "vhdx" | "qcow2" | "hdd" | "ova" | "ovf"
        | "box" | "wim" | "ipsw" => Kind::Archives,
        "pdf" | "doc" | "docx" | "docm" | "dot" | "dotx" | "xls" | "xlsx" | "xlsm" | "xlsb"
        | "ppt" | "pptx" | "pptm" | "pps" | "ppsx" | "odt" | "ods" | "odp" | "odg" | "rtf"
        | "txt" | "text" | "md" | "markdown" | "rst" | "tex" | "epub" | "mobi" | "azw" | "azw3"
        | "djvu" | "csv" | "tsv" | "xps" | "oxps" | "wpd" | "wps" | "eml" | "emlx" | "msg"
        | "mbox" | "vcf" | "ics" | "one" | "nb" => Kind::Documents,
        "rs" | "swift" | "c" | "h" | "cc" | "cpp" | "cxx" | "hh" | "hpp" | "hxx" | "m" | "mm"
        | "py" | "pyi" | "pyc" | "pyo" | "ipynb" | "js" | "mjs" | "cjs" | "jsx" | "ts" | "cts"
        | "tsx" | "java" | "class" | "jar" | "kt" | "kts" | "go" | "rb" | "php" | "cs" | "fs"
        | "vb" | "scala" | "sc" | "groovy" | "gradle" | "dart" | "lua" | "pl" | "pm" | "r"
        | "jl" | "ex" | "exs" | "erl" | "hrl" | "hs" | "ml" | "mli" | "clj" | "cljs" | "elm"
        | "zig" | "nim" | "v" | "sv" | "vhdl" | "asm" | "s" | "sh" | "bash" | "zsh" | "fish"
        | "ps1" | "bat" | "cmd" | "sql" | "html" | "htm" | "css" | "scss" | "sass" | "less"
        | "vue" | "svelte" | "astro" | "json" | "jsonl" | "yaml" | "yml" | "toml" | "xml"
        | "xib" | "storyboard" | "pbxproj" | "xcworkspacedata" | "xcscheme" | "lock" | "proto"
        | "graphql" | "wasm" | "o" | "obj" | "rlib" | "rmeta" | "d" | "pch" | "pcm"
        | "swiftmodule" | "swiftdoc" | "swiftinterface" | "map" | "patch" | "diff" => Kind::Code,
        "dylib" | "so" | "dll" | "a" | "lib" | "tbd" | "sys" | "drv" | "kext" | "plist"
        | "strings" | "stringsdict" | "nib" | "car" | "db" | "sqlite" | "sqlite3" | "db3"
        | "sqlitedb" | "wal" | "shm" | "realm" | "store" | "dat" | "bin" | "log" | "cache"
        | "tmp" | "ttf" | "otf" | "ttc" | "dfont" | "woff" | "woff2" | "mobileprovision"
        | "cer" | "crt" | "pem" | "keychain" | "keychain-db" | "asset" => Kind::System,
        _ => Kind::Other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tree::tests::{dir, leaf};
    use std::path::PathBuf;

    fn totals(t: &Tree) -> Vec<(Kind, u64, u64)> {
        t.kind_totals()
            .into_iter()
            .filter(|k| k.count > 0)
            .map(|k| (k.kind, k.size, k.count))
            .collect()
    }

    fn names(t: &Tree, ids: &[NodeId]) -> Vec<String> {
        ids.iter()
            .map(|&id| t.get(id).unwrap().name.clone())
            .collect()
    }

    /// `/r` = Movies/ (trip.MOV 900, clip.mp4 300), Safari.app/ (Contents/ (binary 400,
    /// icon.png 100)), photo.HEIC 200, notes.md 10, `.DS_Store` 5, README 7.
    fn sample() -> Tree {
        let root = dir(
            "/r",
            vec![
                dir("Movies", vec![leaf("trip.MOV", 900), leaf("clip.mp4", 300)]),
                dir(
                    "Safari.app",
                    vec![dir(
                        "Contents",
                        vec![leaf("binary", 400), leaf("icon.png", 100)],
                    )],
                ),
                leaf("photo.HEIC", 200),
                leaf("notes.md", 10),
                leaf(".DS_Store", 5),
                leaf("README", 7),
            ],
        );
        Tree::from_node(root, PathBuf::from("/r"))
    }

    #[test]
    fn extension_is_matched_ignoring_case() {
        assert_eq!(Kind::of_file("Trip.MoV"), Kind::Video);
        assert_eq!(Kind::of_file("archive.tar.GZ"), Kind::Archives);
        assert_eq!(Kind::of_file("main.rs"), Kind::Code);
        assert_eq!(Kind::of_file("song.FLAC"), Kind::Audio);
        assert_eq!(Kind::of_file("libz.dylib"), Kind::System);
        assert_eq!(Kind::of_file("Report.PDF"), Kind::Documents);
    }

    #[test]
    fn names_without_a_real_extension_are_other() {
        assert_eq!(Kind::of_file(".DS_Store"), Kind::Other);
        assert_eq!(Kind::of_file("Makefile"), Kind::Other);
        assert_eq!(Kind::of_file("trailing."), Kind::Other);
        assert_eq!(Kind::of_file("x.averyveryverylongextension"), Kind::Other);
        assert_eq!(Kind::of_file("video.mövie"), Kind::Other);
    }

    #[test]
    fn packages_are_recognised_by_folder_extension() {
        assert_eq!(Kind::of_package("Xcode.APP"), Some(Kind::Apps));
        assert_eq!(
            Kind::of_package("Backup.sparsebundle"),
            Some(Kind::Archives)
        );
        assert_eq!(Kind::of_package("Sparkle.framework"), Some(Kind::System));
        assert_eq!(Kind::of_package("Projects"), None);
        assert_eq!(Kind::of_package("photos.zip"), None);
    }

    #[test]
    fn kind_totals_count_app_bundles_as_one_item() {
        let t = sample();
        assert_eq!(
            totals(&t),
            vec![
                (Kind::Video, 1200, 2),
                (Kind::Images, 200, 1), // icon.png inside the app is not counted here
                (Kind::Documents, 10, 1),
                (Kind::Apps, 500, 1),
                (Kind::Other, 12, 2),
            ]
        );
    }

    #[test]
    fn kind_totals_add_up_to_the_root_size() {
        let t = sample();
        let sum: u64 = t.kind_totals().iter().map(|k| k.size).sum();
        assert_eq!(sum, t.get(t.root()).unwrap().size);
        assert_eq!(t.kind_totals().len(), Kind::ALL.len());
    }

    #[test]
    fn largest_of_kind_returns_biggest_first() {
        let t = sample();
        let video = t.largest_of_kind(Kind::Video, 10);
        assert_eq!(names(&t, &video), vec!["trip.MOV", "clip.mp4"]);
        assert_eq!(
            names(&t, &t.largest_of_kind(Kind::Video, 1)),
            vec!["trip.MOV"]
        );
        assert_eq!(
            names(&t, &t.largest_of_kind(Kind::Apps, 5)),
            vec!["Safari.app"]
        );
        assert_eq!(t.largest_of_kind(Kind::Audio, 5), Vec::<NodeId>::new());
        assert_eq!(t.largest_of_kind(Kind::Video, 0), Vec::<NodeId>::new());
    }

    #[test]
    fn largest_of_kind_skips_removed_entries() {
        let mut t = sample();
        let trip = t.find(std::path::Path::new("/r/Movies/trip.MOV")).unwrap();
        t.remove(trip);
        assert_eq!(
            names(&t, &t.largest_of_kind(Kind::Video, 10)),
            vec!["clip.mp4"]
        );
    }
}
