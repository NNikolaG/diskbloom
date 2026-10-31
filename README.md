<p align="center"><img src="macos/Resources/AppIcon.png" width="160" alt="Diskbloom icon"></p>

# Diskbloom

**See what's eating your Mac's disk, then clean it up.**

Diskbloom is a disk usage analyzer for macOS with an interactive sunburst map,
a Collector for safe batch deletion, and a Smart Clean mode that finds
regenerable junk such as build folders, dependency caches and Xcode DerivedData.
The scanning engine is written in Rust and the app is native SwiftUI.

> Status: early prototype (v0.1). Expect rough edges.

## Features

- **Fast parallel scanner** (Rust + rayon). It measures *allocated* size (`st_blocks`)
  rather than logical length, counts hard links once, never follows symlinks and stays
  on one volume.
- **Sunburst map**: rings show depth and angle shows size. Tiny items are merged into
  "smaller objects". Click to zoom in, click the center to go back.
- **Percent of parent and of disk** for every item, with a proportion bar in the list.
- **Collector**: while browsing, click the trash icon on any row (or drag it to the tray)
  to queue it. See the total, then move everything to the Trash in one step. The map
  dims queued items and updates in place with no rescan.
- **Smart Clean**: context-aware rules. For example, `target/` is only flagged when a
  `Cargo.toml` sits next to it, and `node_modules/` only next to a `package.json`.
- **Hidden space**: shows the difference between what the volume reports as used and
  what the scan could see (system volume, snapshots, folders without permission).
- **CLI** (`bloom`): terminal tree, a standalone HTML sunburst and a dry-run-first cleaner.
  It also works on Linux.

## Build the macOS app

Requirements: macOS 13+, Xcode Command Line Tools (`xcode-select --install`, full Xcode
is not needed) and Rust ([rustup](https://rustup.rs) or `brew install rust`).

```bash
./macos/build.sh             # this Mac's architecture
./macos/build.sh --universal # arm64 + x86_64
open macos/build/Diskbloom.app
```

For a complete scan, grant **Full Disk Access** in System Settings → Privacy & Security.
The app shows a banner with a shortcut when folders were inaccessible.

## CLI

```bash
cargo install --path crates/cli

bloom top ~ -d 2 -n 10                 # biggest folders as a tree
bloom map ~ -o map.html                # interactive sunburst in one HTML file
bloom clean ~/code                     # dry run: what could be removed
bloom clean ~/code --delete -c rust-build,node-deps --min-mb 50
```

## Clean categories

| Category | Matches |
|---|---|
| `rust-build` | `target/` next to `Cargo.toml` |
| `node-deps` | `node_modules/` next to `package.json` |
| `js-build` | `.next/`, `.nuxt/` next to `package.json` |
| `python-cache` | `__pycache__/`, `.pytest_cache/`, `.mypy_cache/`, `.ruff_cache/` |
| `gradle` | `.gradle/`, and `build/` next to `build.gradle(.kts)` |
| `user-cache` | `~/.cache`, `~/Library/Caches` |
| `pkg-cache` | `~/.npm/_cacache`, `~/.cargo/registry/cache`, `~/.gradle/caches` |
| `xcode` | `~/Library/Developer/Xcode/DerivedData` |
| `trash` | `~/.Trash`, `~/.local/share/Trash` |
| `macos-junk` | `.DS_Store` |

## Project layout

```
crates/core   scanner, arena tree, sunburst layout, clean rules (unit tested)
crates/cli    `bloom` command line tool
crates/ffi    UniFFI bindings exposing the core to Swift
macos/        SwiftUI app (Swift Package) + build.sh
docs/         architecture notes
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how disk analyzers like this work
and how each piece maps to the code.

## License

MIT. Diskbloom is an independent project and is not affiliated with DaisyDisk.
