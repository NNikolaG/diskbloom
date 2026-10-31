<p align="center"><img src="macos/Resources/AppIcon.png" width="160" alt="Diskbloom icon"></p>

# Diskbloom

**See what's eating your Mac's disk, then clean it up.**

Diskbloom is a disk usage analyzer for macOS with an interactive sunburst map,
a Collector for safe batch deletion, and a Smart Clean mode that finds
regenerable junk such as build folders, dependency caches and Xcode DerivedData.
The scanning engine is written in Rust and the app is native SwiftUI.

> Status: early version (v0.2). Expect rough edges. English and Serbian interface.

## Features

- **Disk overview**: click a disk to see used / purgeable / free space and pick an action:
  scan, Smart Clean, scan only Home, empty Trash, open Storage settings, reveal, eject.
- **Fast parallel scanner** (Rust + rayon). It measures *allocated* size (`st_blocks`)
  rather than logical length, counts hard links once, never follows symlinks and stays
  on one volume.
- **Sunburst map**: rings show depth and angle shows size. Tiny items are merged into
  "smaller objects". Click to zoom in, click the center to go back.
- **Percent of parent and of disk** for every item, with a proportion bar in the list.
- **Collector**: while browsing, click the trash icon on any row (or drag it to the tray)
  to queue it. See the total, then move everything to the Trash in one step. The map
  dims queued items and updates in place with no rescan.
- **Smart Clean**: finds build folders, package and app caches, Xcode DerivedData, iOS
  simulators, Android emulators, VM disks, old installers and more (see
  [categories](#clean-categories)). Rules are context-aware: for example, `target/` is only
  flagged next to a `Cargo.toml`. Regenerable items are preselected; emulators, VMs and
  backups are only listed for you to review.
- **Largest files**: the 300 biggest files with when you last opened them (from Spotlight),
  filterable to "not opened in 6 months / a year".
- **Duplicates**: finds identical files (size, then a hash of the first 64 KB, then a full
  BLAKE3 hash). "Keep one" queues the other copies for the Trash.
- **Time Machine local snapshots**: listed in the disk overview and removable (asks for
  your admin password). These are often the biggest part of "purgeable" space.
- **Proper cleanup for developer tools**: iOS simulators are removed with `xcrun simctl`,
  Android emulators together with their `.ini`, and the Docker disk is never deleted;
  Diskbloom offers `docker system prune` instead.
- **Quick Look** (Space), **refresh one folder** without rescanning everything (⌘R), and
  keyboard shortcuts for the views (⌘1 map, ⌘2 largest files, ⌘3 duplicates, ⌘K Smart Clean).
- **Hidden space**: shows the difference between what the volume reports as used and
  what the scan could see (system volume, snapshots, folders without permission).
- **CLI** (`bloom`): terminal tree, a standalone HTML sunburst and a dry-run-first cleaner.
  It also works on Linux.

## Install

Diskbloom is not on the App Store yet, so you either download a CI build or build it
yourself. Both take a few minutes.

### Option A: download a release

1. Download the latest **Diskbloom-x.y.z.dmg** from
   [Releases](https://github.com/NNikolaG/diskbloom/releases/latest). Release builds are for
   Apple Silicon Macs (M1 or newer); on an Intel Mac, build from source (Option B).
2. Open the DMG and drag **Diskbloom** to **Applications**.
3. The app is not notarized by Apple, so macOS blocks it on first launch. Either
   right-click the app → **Open** → **Open**, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Diskbloom.app
   ```

### Option B: build from source

Requirements: macOS 13 Ventura or newer, Apple Silicon or Intel.

1. **Xcode Command Line Tools** (full Xcode is not needed):
   ```bash
   xcode-select --install
   ```
2. **Rust**, either with rustup (recommended, also allows universal builds):
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```
   or with Homebrew: `brew install rust`. Open a new terminal afterwards.
3. **Build and install** into `/Applications`:
   ```bash
   git clone https://github.com/NNikolaG/diskbloom.git
   cd diskbloom
   ./macos/build.sh --install
   open -a Diskbloom
   ```

`build.sh` options:

| Command | What it does |
|---|---|
| `./macos/build.sh` | builds `macos/build/Diskbloom.app` for this Mac |
| `./macos/build.sh --install` | builds and replaces `/Applications/Diskbloom.app` (quits the running app first) |
| `./macos/build.sh --universal` | arm64 + x86_64 in one app (needs rustup) |

### Updating

With a release: download the new DMG and drag Diskbloom to Applications again; macOS asks
to replace the old version. From source, you never need to delete the old version by hand:

```bash
cd diskbloom
git pull
./macos/build.sh --install
```

### Full Disk Access

Without it macOS hides parts of your disk (Mail, Messages, Safari data, other users,
some caches), and Diskbloom shows a yellow banner with the number of inaccessible folders.

1. Open **System Settings → Privacy & Security → Full Disk Access** (the banner and the
   disk overview have a button for this).
2. Turn on **Diskbloom** (use **+** to add it from Applications if it's missing).
3. Quit and reopen Diskbloom.

**Why it may ask again after every build:** an app built without an Apple certificate
gets a new ad-hoc signature each time, and macOS treats every build as a different app.
To keep the permission across updates, add your Apple ID once in **Xcode → Settings →
Accounts** (a free account is enough). `build.sh` then finds the "Apple Development"
certificate and signs with it automatically. To use a specific certificate, set it
explicitly:

```bash
DISKBLOOM_SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" ./macos/build.sh --install
```

### Troubleshooting

| Problem | Fix |
|---|---|
| `rustup: command not found` / `cargo: command not found` | Install Rust (step 2) and open a new terminal. |
| `xcrun: error: invalid active developer path` | Run `xcode-select --install`. |
| "Diskbloom can't be opened because Apple cannot check it" | Right-click → **Open**, or remove the quarantine flag (Option A, step 3). |
| Scanning **Macintosh HD** shows less than Finder | Grant Full Disk Access. The rest is system data and snapshots, shown as *hidden space*. |
| Emptying the Trash asks to control Finder | Expected. Diskbloom empties the Trash through Finder, so allow it once. |

### Uninstall

```bash
rm -rf /Applications/Diskbloom.app
```

Diskbloom keeps no settings or caches of its own.

## CLI

```bash
cargo install --path crates/cli

bloom top ~ -d 2 -n 10                 # biggest folders as a tree
bloom map ~ -o map.html                # interactive sunburst in one HTML file
bloom clean ~/code                     # dry run: what could be removed
bloom clean ~/code --delete -c rust-build,node-deps --min-mb 50
```

## Clean categories

**Safe** categories regenerate on their own and are preselected. **Review** categories
(emulators, VMs, backups, installers) are listed but never preselected. The CLI only
includes them with `--include-review`.

| Category | Matches | |
|---|---|---|
| `rust-build` | `target/` next to `Cargo.toml` | safe |
| `node-deps` | `node_modules/` next to `package.json` | safe |
| `js-build` | `.next/`, `.nuxt/`, `.turbo/` next to `package.json` | safe |
| `python-cache` | `__pycache__/`, `.pytest_cache/`, `.mypy_cache/`, `.ruff_cache/` | safe |
| `python-venv` | any folder containing `pyvenv.cfg` | review |
| `gradle` | `.gradle/`, and `build/` next to `build.gradle(.kts)` | safe |
| `cocoapods` / `swift-build` | `Pods/` next to `Podfile`, `.build/` next to `Package.swift` | safe |
| `xcode-derived` | Xcode DerivedData, `~/Library/Caches/com.apple.dt.Xcode` | safe |
| `xcode-device-support` | each iOS / watchOS / tvOS / visionOS DeviceSupport version | safe |
| `xcode-archives` | each folder in Xcode Archives | review |
| `simulators` | each iOS simulator device in `CoreSimulator/Devices` | review |
| `simulator-cache` | `CoreSimulator/Caches` | safe |
| `android-emulators` | each `~/.android/avd/*.avd` | review |
| `android-images` | each Android SDK system image | review |
| `vms` | Docker Desktop disk, UTM, Parallels and VMware VMs | review |
| `pkg-cache` | Homebrew, pip, Yarn, pnpm, CocoaPods, npm, Cargo, Gradle, Maven, Go, NuGet, Bun caches | safe |
| `app-cache` | each folder in `~/Library/Caches`, and `~/.cache` | safe |
| `logs` | `~/Library/Logs` | safe |
| `ios-backups` | each iPhone/iPad backup in MobileSync | review |
| `installers` | `.dmg`, `.pkg`, `.iso`, `.xip` in `~/Downloads` | review |
| `trash` | `~/.Trash`, `~/.local/share/Trash` | review |

## Language

The interface follows the macOS language setting: English by default, Serbian (Latin) when
Serbian is first in **System Settings → General → Language & Region**. Translations live in
`macos/Resources/<lang>.lproj/Localizable.strings`; the keys are the English texts, so adding
a language means copying `sr.lproj` and translating the right-hand side.

## Releasing

Push a tag and GitHub Actions builds an Apple Silicon DMG and publishes the release (free for
public repositories):

```bash
git tag v0.3.0 && git push origin v0.3.0
```

## Project layout

```
crates/core   scanner, arena tree, sunburst layout, clean rules, duplicate finder (unit tested)
crates/cli    `bloom` command line tool
crates/ffi    UniFFI bindings exposing the core to Swift
macos/        SwiftUI app (Swift Package) + build.sh
docs/         architecture notes
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how disk analyzers like this work
and how each piece maps to the code.

## License

MIT. Diskbloom is an independent project and is not affiliated with DaisyDisk.
