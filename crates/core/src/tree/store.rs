//! Saving a scan to disk and loading it back, so the app can show the last scan right
//! away and then only rescan what changed.
//!
//! The format is a small binary file: a header, then the attached entries in pre-order
//! (each followed by its child count). Detached entries are not written. All integers
//! are little-endian.

use super::{Entry, NodeId, Tree};
use std::io::{self, Read, Write};
use std::path::PathBuf;

const MAGIC: &[u8; 8] = b"DBTREE\0\x01";
/// Upper bounds that a valid file never reaches; they keep a damaged file from causing
/// huge allocations.
const MAX_NAME: u32 = 64 * 1024;
const MAX_ENTRIES: u64 = 200_000_000;

/// Information saved next to the tree.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct ScanInfo {
    /// When the scan was made (Unix seconds).
    pub scanned_at: i64,
    /// An opaque marker from the caller, e.g. the `FSEvents` event id at scan time.
    pub event_id: u64,
}

impl Tree {
    /// Writes the attached part of the tree.
    ///
    /// # Errors
    /// Fails if writing fails.
    pub fn save(&self, mut out: impl Write, info: ScanInfo) -> io::Result<()> {
        out.write_all(MAGIC)?;
        write_bytes(&mut out, self.root_path.to_string_lossy().as_bytes())?;
        out.write_all(&info.scanned_at.to_le_bytes())?;
        out.write_all(&info.event_id.to_le_bytes())?;
        let count = self.attached_count();
        out.write_all(&count.to_le_bytes())?;
        let mut stack = vec![self.root()];
        while let Some(id) = stack.pop() {
            let e = self.entry(id);
            write_bytes(&mut out, e.name.as_bytes())?;
            out.write_all(&e.size.to_le_bytes())?;
            out.write_all(&e.files.to_le_bytes())?;
            out.write_all(&e.newest.to_le_bytes())?;
            out.write_all(&[u8::from(e.is_dir)])?;
            out.write_all(&(e.children.len() as u32).to_le_bytes())?;
            // Reverse so that children come out in their sorted order.
            stack.extend(e.children.iter().rev().copied());
        }
        out.flush()
    }

    /// Number of entries reachable from the root.
    fn attached_count(&self) -> u64 {
        let mut count = 0;
        let mut stack = vec![self.root()];
        while let Some(id) = stack.pop() {
            count += 1;
            stack.extend(self.entry(id).children.iter().copied());
        }
        count
    }

    /// Reads a tree written by [`Tree::save`].
    ///
    /// # Errors
    /// Fails if reading fails or the data is not a valid saved tree.
    pub fn load(mut input: impl Read) -> io::Result<(Tree, ScanInfo)> {
        let mut magic = [0u8; 8];
        input.read_exact(&mut magic)?;
        if &magic != MAGIC {
            return Err(invalid("not a Diskbloom scan file"));
        }
        let root_path = PathBuf::from(read_string(&mut input)?);
        let info = ScanInfo {
            scanned_at: i64::from_le_bytes(read_array(&mut input)?),
            event_id: u64::from_le_bytes(read_array(&mut input)?),
        };
        let count = u64::from_le_bytes(read_array(&mut input)?);
        if count == 0 || count > MAX_ENTRIES {
            return Err(invalid("bad entry count"));
        }
        let mut entries: Vec<Entry> = Vec::with_capacity(count.min(1 << 20) as usize);
        // (entry id, children still to read)
        let mut open: Vec<(NodeId, u32)> = Vec::new();
        for _ in 0..count {
            let name = read_string(&mut input)?;
            let size = u64::from_le_bytes(read_array(&mut input)?);
            let files = u64::from_le_bytes(read_array(&mut input)?);
            let newest = i64::from_le_bytes(read_array(&mut input)?);
            let [is_dir] = read_array::<1>(&mut input)?;
            let child_count = u32::from_le_bytes(read_array(&mut input)?);

            let id = entries.len() as NodeId;
            let parent = match open.last_mut() {
                Some((parent, left)) => {
                    *left -= 1;
                    Some(*parent)
                }
                None if entries.is_empty() => None,
                None => return Err(invalid("more than one root")),
            };
            if let Some(p) = parent {
                entries[p as usize].children.push(id);
            }
            entries.push(Entry {
                name,
                size,
                files,
                is_dir: is_dir != 0,
                newest,
                parent,
                children: Vec::with_capacity(child_count.min(1 << 16) as usize),
            });
            while open.last().is_some_and(|&(_, left)| left == 0) {
                open.pop();
            }
            if child_count > 0 {
                open.push((id, child_count));
            }
        }
        if !open.is_empty() {
            return Err(invalid("truncated tree"));
        }
        Ok((Tree { entries, root_path }, info))
    }
}

fn invalid(msg: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, msg.to_owned())
}

fn write_bytes(out: &mut impl Write, bytes: &[u8]) -> io::Result<()> {
    let len = u32::try_from(bytes.len()).map_err(|_| invalid("name too long"))?;
    out.write_all(&len.to_le_bytes())?;
    out.write_all(bytes)
}

fn read_array<const N: usize>(input: &mut impl Read) -> io::Result<[u8; N]> {
    let mut buf = [0u8; N];
    input.read_exact(&mut buf)?;
    Ok(buf)
}

fn read_string(input: &mut impl Read) -> io::Result<String> {
    let len = u32::from_le_bytes(read_array(input)?);
    if len > MAX_NAME {
        return Err(invalid("name too long"));
    }
    let mut buf = vec![0u8; len as usize];
    input.read_exact(&mut buf)?;
    String::from_utf8(buf).map_err(|_| invalid("name is not UTF-8"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tree::tests::sample;
    use std::path::Path;

    fn names(t: &Tree) -> Vec<String> {
        let mut out = Vec::new();
        let mut stack = vec![t.root()];
        while let Some(id) = stack.pop() {
            let e = t.get(id).unwrap();
            out.push(format!("{}:{}:{}", t.path(id).display(), e.size, e.files));
            stack.extend(e.children.iter().rev().copied());
        }
        out
    }

    #[test]
    fn save_and_load_round_trip() {
        let t = sample();
        let info = ScanInfo {
            scanned_at: 1_700_000_000,
            event_id: 42,
        };
        let mut buf = Vec::new();
        t.save(&mut buf, info).unwrap();
        let (loaded, loaded_info) = Tree::load(buf.as_slice()).unwrap();
        assert_eq!(loaded_info, info);
        assert_eq!(loaded.root_path(), t.root_path());
        assert_eq!(names(&loaded), names(&t));
        assert!(loaded.find(Path::new("/r/a/a2")).is_some());
    }

    #[test]
    fn detached_entries_are_not_saved() {
        let mut t = sample();
        let a = t.find(Path::new("/r/a")).unwrap();
        t.remove(a);
        let mut buf = Vec::new();
        t.save(&mut buf, ScanInfo::default()).unwrap();
        let (loaded, _) = Tree::load(buf.as_slice()).unwrap();
        assert_eq!(loaded.len(), t.len() - 3); // a, a1, a2
        assert_eq!(loaded.find(Path::new("/r/a")), None);
        assert_eq!(loaded.get(0).unwrap().size, t.get(0).unwrap().size);
    }

    #[test]
    fn damaged_files_are_rejected() {
        let mut buf = Vec::new();
        sample().save(&mut buf, ScanInfo::default()).unwrap();
        assert!(Tree::load(&buf[..buf.len() - 3]).is_err()); // truncated
        assert!(Tree::load(&b"NOTATREE"[..]).is_err());
        let mut bad = buf.clone();
        bad[8..12].copy_from_slice(&u32::MAX.to_le_bytes()); // absurd name length
        assert!(Tree::load(bad.as_slice()).is_err());
    }
}
