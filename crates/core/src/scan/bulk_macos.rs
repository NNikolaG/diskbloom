//! Reads a whole folder with `getattrlistbulk(2)`: names and the attributes the scanner
//! needs for many entries per system call, instead of one `fstatat` per entry.
//!
//! This is the only module in the workspace that may use `unsafe`, for the one system
//! call. The returned buffer is parsed in safe Rust: every read is bounds-checked, and
//! a malformed buffer is an error, after which the caller reads the folder the
//! portable way.

#![allow(unsafe_code)]

use super::{Info, to_i64, to_u64};
use rustix::fs::FileType;
use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::io;
use std::os::fd::{AsRawFd, BorrowedFd};

/// Not in the `libc` crate. Packed right after `ATTR_CMN_RETURNED_ATTRS` (see
/// `getattrlistbulk(2)`).
const ATTR_CMN_ERROR: u32 = 0x2000_0000;

const COMMON: u32 = libc::ATTR_CMN_RETURNED_ATTRS
    | ATTR_CMN_ERROR
    | libc::ATTR_CMN_NAME
    | libc::ATTR_CMN_DEVID
    | libc::ATTR_CMN_OBJTYPE
    | libc::ATTR_CMN_MODTIME
    | libc::ATTR_CMN_FILEID;
const DIR: u32 = libc::ATTR_DIR_MOUNTSTATUS | libc::ATTR_DIR_ALLOCSIZE;
const FILE: u32 = libc::ATTR_FILE_LINKCOUNT | libc::ATTR_FILE_ALLOCSIZE;

/// `enum vtype` from `<sys/vnode.h>`, the value of `ATTR_CMN_OBJTYPE`.
fn file_type(vtype: u32) -> FileType {
    match vtype {
        1 => FileType::RegularFile,
        2 => FileType::Directory,
        3 => FileType::BlockDevice,
        4 => FileType::CharacterDevice,
        5 => FileType::Symlink,
        6 => FileType::Socket,
        7 => FileType::Fifo,
        _ => FileType::Unknown,
    }
}

/// Output buffer size. Each call fills it with as many entries as fit (about 70 bytes
/// plus the name each).
const BUF_SIZE: usize = 64 * 1024;

thread_local! {
    static BUF: RefCell<Vec<u8>> = RefCell::new(vec![0; BUF_SIZE]);
}

/// One folder entry. `info` is `None` when the kernel did not return everything the
/// scanner needs (per-entry error, missing attribute, mount point); the caller then
/// `fstatat`s the name, exactly as the portable path does.
pub(super) struct Entry {
    pub name: CString,
    pub info: Option<Info>,
}

/// All entries of the open folder `fd` (without `.` and `..`), plus the number of
/// entries that came back without a name and so cannot be stat-ed (counted as errors).
///
/// Moves the folder's read offset; the caller rewinds before reading it another way.
///
/// # Errors
/// Fails if the system call fails (`ENOTSUP` on file systems without bulk support,
/// for example) or returns a buffer that does not parse.
pub(super) fn read(fd: BorrowedFd<'_>) -> io::Result<(Vec<Entry>, u64)> {
    BUF.with_borrow_mut(|buf| {
        let mut entries = Vec::new();
        let mut unnamed = 0;
        loop {
            let count = getattrlistbulk(fd, buf)?;
            if count == 0 {
                return Ok((entries, unnamed));
            }
            let mut rest: &[u8] = buf;
            for _ in 0..count {
                let len = Reader::new(rest, 0).u32()? as usize;
                if len < 4 || len > rest.len() {
                    return Err(Malformed.into());
                }
                let (entry, next) = rest.split_at(len);
                match parse(entry)? {
                    Some(entry) => entries.push(entry),
                    None => unnamed += 1,
                }
                rest = next;
            }
        }
    })
}

/// The buffer does not hold what was asked for.
struct Malformed;

impl From<Malformed> for io::Error {
    fn from(_: Malformed) -> Self {
        io::Error::new(
            io::ErrorKind::InvalidData,
            "malformed getattrlistbulk buffer",
        )
    }
}

/// One call: fills `buf` and returns the number of entries in it (0 at the end).
fn getattrlistbulk(fd: BorrowedFd<'_>, buf: &mut [u8]) -> io::Result<usize> {
    let mut list = libc::attrlist {
        bitmapcount: libc::ATTR_BIT_MAP_COUNT,
        reserved: 0,
        commonattr: COMMON,
        volattr: 0,
        dirattr: DIR,
        fileattr: FILE,
        forkattr: 0,
    };
    // SAFETY: `fd` is a valid open descriptor for the borrow's lifetime. `list` is a
    // properly initialised `struct attrlist` that outlives the call and is only read.
    // The kernel writes at most `buf.len()` bytes into `buf`, which is a live, exclusive,
    // already-initialised byte slice, so no uninitialised memory is ever read back.
    let count = unsafe {
        libc::getattrlistbulk(
            fd.as_raw_fd(),
            (&raw mut list).cast(),
            buf.as_mut_ptr().cast(),
            buf.len(),
            0,
        )
    };
    usize::try_from(count).map_err(|_| io::Error::last_os_error())
}

/// Bounds-checked native-endian reads at a moving offset. Attributes are packed on
/// 4-byte boundaries, so 8-byte values may be unaligned; they are copied, not cast.
struct Reader<'a> {
    buf: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn new(buf: &'a [u8], pos: usize) -> Self {
        Self { buf, pos }
    }

    fn bytes<const N: usize>(&mut self) -> Result<[u8; N], Malformed> {
        let end = self.pos.checked_add(N).ok_or(Malformed)?;
        let bytes = self.buf.get(self.pos..end).ok_or(Malformed)?;
        self.pos = end;
        bytes.try_into().map_err(|_| Malformed)
    }

    fn u32(&mut self) -> Result<u32, Malformed> {
        self.bytes().map(u32::from_ne_bytes)
    }

    fn i32(&mut self) -> Result<i32, Malformed> {
        self.bytes().map(i32::from_ne_bytes)
    }

    fn u64(&mut self) -> Result<u64, Malformed> {
        self.bytes().map(u64::from_ne_bytes)
    }

    fn i64(&mut self) -> Result<i64, Malformed> {
        self.bytes().map(i64::from_ne_bytes)
    }

    /// Reads a value only if the kernel returned it (`bit` set in `returned`).
    fn opt<T>(
        &mut self,
        returned: u32,
        bit: u32,
        f: fn(&mut Self) -> Result<T, Malformed>,
    ) -> Result<Option<T>, Malformed> {
        if returned & bit == 0 {
            Ok(None)
        } else {
            f(self).map(Some)
        }
    }
}

/// Parses one entry; `None` if it has no name.
///
/// Layout: `u32` length, `attribute_set_t` returned, then each returned attribute in
/// bit order of its group (common, dir, file), except `ATTR_CMN_ERROR`, which comes
/// first. Directories carry no file attributes and files no directory attributes.
fn parse(entry: &[u8]) -> Result<Option<Entry>, Malformed> {
    let mut r = Reader::new(entry, 4);
    let common = r.u32()?;
    let _vol = r.u32()?;
    let dir = r.u32()?;
    let file = r.u32()?;
    let _fork = r.u32()?;

    let error = r.opt(common, ATTR_CMN_ERROR, Reader::u32)?;
    let Some(name) = r.opt(common, libc::ATTR_CMN_NAME, name)? else {
        return Ok(None);
    };
    let raw = Raw {
        error,
        dev: r.opt(common, libc::ATTR_CMN_DEVID, Reader::i32)?,
        vtype: r.opt(common, libc::ATTR_CMN_OBJTYPE, Reader::u32)?,
        mtime: r.opt(common, libc::ATTR_CMN_MODTIME, |r| {
            // `struct timespec` of a 64-bit process: seconds, then nanoseconds.
            let sec = r.i64()?;
            r.i64()?;
            Ok(sec)
        })?,
        ino: r.opt(common, libc::ATTR_CMN_FILEID, Reader::u64)?,
        mount_status: r.opt(dir, libc::ATTR_DIR_MOUNTSTATUS, Reader::u32)?,
        dir_alloc: r.opt(dir, libc::ATTR_DIR_ALLOCSIZE, Reader::i64)?,
        nlink: r.opt(file, libc::ATTR_FILE_LINKCOUNT, Reader::u32)?,
        file_alloc: r.opt(file, libc::ATTR_FILE_ALLOCSIZE, Reader::i64)?,
    };
    let info = raw.info();
    Ok(Some(Entry { name, info }))
}

/// The attributes of one entry, each `None` if the kernel did not return it.
struct Raw {
    error: Option<u32>,
    dev: Option<i32>,
    vtype: Option<u32>,
    mtime: Option<i64>,
    ino: Option<u64>,
    mount_status: Option<u32>,
    dir_alloc: Option<i64>,
    nlink: Option<u32>,
    file_alloc: Option<i64>,
}

impl Raw {
    /// What `fstatat` would report, or `None` if the entry has to be stat-ed instead.
    fn info(&self) -> Option<Info> {
        if self.error.is_some_and(|e| e != 0) {
            return None;
        }
        let kind = file_type(self.vtype?);
        let (alloc, nlink) = if kind == FileType::Directory {
            // A mount point reports the covered folder, not the mounted volume's root
            // that `fstatat` sees, so it is stat-ed to keep the volume check right.
            if self.mount_status? != 0 {
                return None;
            }
            (self.dir_alloc?, 1)
        } else {
            (self.file_alloc?, self.nlink?)
        };
        Some(Info {
            kind,
            // `st_blocks` is the allocation rounded up to 512-byte units.
            size: to_u64(alloc).div_ceil(512) * 512,
            dev: to_u64(self.dev?),
            ino: self.ino?,
            nlink: u64::from(nlink),
            mtime: to_i64(self.mtime?),
        })
    }
}

/// Reads an `attrreference_t` (offset from the reference itself, length including the
/// terminating NUL) and the name it points to inside the same entry.
fn name(r: &mut Reader<'_>) -> Result<CString, Malformed> {
    let start = r.pos;
    let offset = usize::try_from(r.i32()?).map_err(|_| Malformed)?;
    let len = r.u32()? as usize;
    let from = start.checked_add(offset).ok_or(Malformed)?;
    let to = from.checked_add(len).ok_or(Malformed)?;
    let bytes = r.buf.get(from..to).ok_or(Malformed)?;
    match CStr::from_bytes_until_nul(bytes) {
        Ok(name) if !name.is_empty() => Ok(name.to_owned()),
        _ => Err(Malformed),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A file entry packed as the kernel does, with `common` and `file` attributes.
    fn file_entry(common: u32, file: u32, name: &[u8]) -> Vec<u8> {
        let mut e = Vec::new();
        e.extend_from_slice(&0u32.to_ne_bytes()); // length, set below
        for group in [common, 0, 0, file, 0] {
            e.extend_from_slice(&group.to_ne_bytes());
        }
        if common & ATTR_CMN_ERROR != 0 {
            e.extend_from_slice(&13u32.to_ne_bytes());
        }
        let name_ref = e.len();
        if common & libc::ATTR_CMN_NAME != 0 {
            e.extend_from_slice(&[0; 8]);
        }
        e.extend_from_slice(&7i32.to_ne_bytes()); // dev
        e.extend_from_slice(&1u32.to_ne_bytes()); // VREG
        e.extend_from_slice(&1_700_000_000i64.to_ne_bytes());
        e.extend_from_slice(&5i64.to_ne_bytes()); // nanoseconds
        e.extend_from_slice(&42u64.to_ne_bytes()); // file id
        if file & libc::ATTR_FILE_LINKCOUNT != 0 {
            e.extend_from_slice(&2u32.to_ne_bytes());
        }
        if file & libc::ATTR_FILE_ALLOCSIZE != 0 {
            e.extend_from_slice(&4097i64.to_ne_bytes());
        }
        if common & libc::ATTR_CMN_NAME != 0 {
            let offset = i32::try_from(e.len() - name_ref).unwrap();
            let len = u32::try_from(name.len()).unwrap();
            e[name_ref..name_ref + 4].copy_from_slice(&offset.to_ne_bytes());
            e[name_ref + 4..name_ref + 8].copy_from_slice(&len.to_ne_bytes());
            e.extend_from_slice(name);
        }
        let len = u32::try_from(e.len()).unwrap();
        e[..4].copy_from_slice(&len.to_ne_bytes());
        e
    }

    const ALL: u32 = COMMON & !ATTR_CMN_ERROR;

    #[test]
    fn parses_a_complete_file_entry() {
        let entry = file_entry(ALL, FILE, b"name\0");
        let parsed = parse(&entry).ok().flatten().unwrap();
        assert_eq!(parsed.name.as_bytes(), b"name");
        let info = parsed.info.unwrap();
        assert_eq!(
            (info.size, info.dev, info.ino, info.nlink, info.mtime),
            (4608, 7, 42, 2, 1_700_000_000)
        );
        assert_eq!(info.kind, FileType::RegularFile);
    }

    #[test]
    fn missing_attribute_or_error_leaves_the_entry_to_fstatat() {
        let no_alloc = file_entry(ALL, libc::ATTR_FILE_LINKCOUNT, b"a\0");
        assert!(parse(&no_alloc).ok().flatten().unwrap().info.is_none());
        let failed = file_entry(ALL | ATTR_CMN_ERROR, FILE, b"b\0");
        let failed = parse(&failed).ok().flatten().unwrap();
        assert_eq!(failed.name.as_bytes(), b"b");
        assert!(failed.info.is_none());
    }

    #[test]
    fn entry_without_name_is_reported_as_unnamed() {
        let entry = file_entry(ALL & !libc::ATTR_CMN_NAME, FILE, b"");
        assert!(matches!(parse(&entry), Ok(None)));
    }

    #[test]
    fn truncated_or_out_of_bounds_entries_are_malformed() {
        let entry = file_entry(ALL, FILE, b"name\0");
        for cut in [3, 10, 30, entry.len() - 1] {
            assert!(parse(&entry[..cut]).is_err(), "cut at {cut}");
        }
        let mut bad = file_entry(ALL, FILE, b"name");
        assert!(parse(&bad).is_err(), "name without NUL");
        bad[28..32].copy_from_slice(&1000u32.to_ne_bytes());
        assert!(parse(&bad).is_err(), "name length past the entry");
    }
}
