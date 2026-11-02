# Diskbloom architecture

How Diskbloom scans a disk, keeps and draws the result, and why the key decisions were
made the way they were.

## Layers

```
 ┌──────────────────────────────────────────────────────────────────────┐
 │ 1. Places            mounted volumes, used / purgeable / free space  │
 ├──────────────────────────────────────────────────────────────────────┤
 │ 2. Scanner (Rust)    parallel walk with rayon                        │
 │                      ├─ one lstat per entry: type, allocated size    │
 │                      ├─ boot disk through /System/Volumes/Data       │
 │                      └─ hard links counted once, stays on one volume │
 ├──────────────────────────────────────────────────────────────────────┤
 │ 3. Tree (Rust)       flat arena of entries addressed by u32 ids      │
 │                      + hidden space = volume used − scanned total    │
 ├──────────────────────────────────────────────────────────────────────┤
 │ 4. Analysis (Rust)   sunburst layout, Smart Clean rules,             │
 │                      largest files, duplicates (size → head → hash)  │
 ├──────────────────────────────────────────────────────────────────────┤
 │ 5. App (SwiftUI)     Canvas sunburst, lists, Trash list, Smart Clean │
 ├──────────────────────────────────────────────────────────────────────┤
 │ 6. Removal           Trash, or the proper tool (simctl, docker,      │
 │                      tmutil); the tree is updated without a rescan   │
 └──────────────────────────────────────────────────────────────────────┘
```

## Key decisions

| Problem | Solution |
|---|---|
| Scan speed | `rayon` walks folders in parallel; SSDs handle many metadata requests at once well |
| Real size | allocated blocks (`st_blocks * 512`), not logical length, so sparse and compressed files are not overcounted |
| Hard links | counted once: a `(dev, ino)` set for files with `nlink > 1` |
| Mount points | the scan stays on the root's volume (`st_dev`); `--cross-fs` in the CLI turns that off |
| Symlinks | `symlink_metadata` everywhere; links are never followed, so no loops or double counting |
| Unreadable folders | counted and skipped; the gap to the volume's used space is shown as hidden space |
| APFS boot disk | `/` is the sealed system volume, so the app scans `/System/Volumes/Data` and converts paths back to `/Users/...` for Finder and the Trash (`core::volume`) |
| Thousands of tiny items | merged into one "smaller objects" segment per folder |
| After a delete | no rescan: `Tree::remove` subtracts the size from every ancestor and keeps the children sorted |
| Large trees in Swift | Swift never receives the whole tree, only ids and what it draws right now |
| Safe deletion | the app moves to the Trash after confirmation; the CLI is a dry run unless `--delete` |

## Data flow

```
 folder ──► Scanner ──► Node ──► Tree ──┬─► layout()           ──► SunburstView
                                       ├─► children()/info()  ──► lists
                                       ├─► clean::find()      ──► Smart Clean
                                       ├─► largest_files()    ──► Largest files
                                       ├─► kind_totals()      ──► File types
                                       ├─► search()           ──► Search
                                       └─► DupeFinder::find() ──► Duplicates
                                                                      │
                     Tree::remove / replace_subtree ◄── Trash / rescan ┘
```

## Code map

```
crates/core            diskbloom-core (library, no I/O besides scanning and hashing)
  scan.rs              Scanner, Node
  tree.rs              Tree (arena), remove, replace_subtree, largest_files
  tree/layout.rs       sunburst geometry
  tree/search.rs       find by name (case- and diacritic-insensitive)
  kinds.rs             file kinds by extension, .app bundles as one item
  clean/               Smart Clean: category.rs (enum), rules.rs (tables), mod.rs (walk)
  dupes.rs             duplicate finder
  volume.rs            /System/Volumes/Data path conversions
crates/cli             `bloom`: top, map (HTML), clean
crates/ffi             UniFFI objects for Swift: ScanJob, DiskTree, DupeJob, plus records

macos/Sources
  DiskbloomFFI/        generated Swift bindings (build.sh)
  DiskbloomKit/        logic without UI: Shell, CleanupMethod, SimulatorRuntimeList,
                       TimeMachineSnapshot, Format, CandidateLabel, LaunchOptions,
                       LowSpaceAlert, APFSClones
                       (tested by swift test)
  Diskbloom/
    App/               entry point, window, menu commands
    Model/             AppModel (state) and its extensions: collector, cleanup, system
    Services/          AppKit glue: TrashMover, SystemActions, volumes, scan cache,
                       FSEvents history, low-space notification
    MenuBar/           menu bar item: DiskStatus (free space, refreshed every minute), its window
    Settings/          the Settings window and its two preferences
    Sidebar/ Overview/ Map/ Collector/ Cleaner/ LargestFiles/ Duplicates/ Types/
    Search/ Snapshots/
    Shared/            small reusable views
```

## The Rust ↔ Swift boundary

`crates/ffi` exposes three objects. Long calls block and run in `Task.detached` on the
Swift side; their progress and cancel methods can be called from any thread meanwhile.

| Object | Blocking call | Progress / cancel |
|---|---|---|
| `ScanJob` | `run() -> DiskTree` | `scanned()`, `errors()`, `cancel()` |
| `DiskTree` | `rescan(id)` | — (reads are concurrent, updates lock briefly) |
| `DupeJob` | `run() -> [DupGroupInfo]` | `progressDone()`, `progressTotal()`, `cancel()` |

Paths returned to Swift are already in their firmlinked form (`/Users/...`), because
macOS refuses Trash moves through `/System/Volumes/Data`. `DiskTree.find` accepts both
forms and paths through symlinks.

## Smart Clean rules

Rules live in `crates/core/src/clean/rules.rs`:

- **Name rules** match a folder anywhere, with a condition: `target/` only next to a
  `Cargo.toml`, `node_modules/` only next to a `package.json`, a virtualenv only if it
  contains `pyvenv.cfg`.
- **Path rules** match known places under `$HOME` (`HOME_RULES`) or absolute ones
  (`SYSTEM_RULES`, simulator runtimes in `/Library`): an exact path (Xcode
  DerivedData), every child of a folder (each cache in `~/Library/Caches`, each
  simulator), children with an extension (`.dmg` in Downloads) or child folders with a
  name prefix (nvm's `v20.11.0`). An exact rule wins; a folder with its own children
  rule (`~/Library/Caches/JetBrains`) is never taken whole by its parent's rule.

Name rules never apply below protected roots (`~/Library`, `/Applications`, version
managers such as `~/.nvm`, editor folders such as `~/.vscode`), inside `.app` bundles,
or inside `node_modules`, so global packages and editor extensions are never offered.
Each category is *safe* (regenerates by itself, preselected) or *review* (emulators,
VMs, simulator runtimes, Node versions, backups, installers: listed, never preselected).

The app removes some categories with their own tool (`DiskbloomKit.CleanupMethod`):
simulators with `xcrun simctl delete <UDID>` (only real UUIDs are accepted), simulator
runtimes with `xcrun simctl runtime delete <identifier>` (the identifier comes from
`simctl runtime list -j`, matched by the image path; `clean::delete` refuses them), Android
emulators together with their `.ini`, the Docker disk image never (the app offers
`docker system prune` instead), and the Trash by emptying it through Finder.
