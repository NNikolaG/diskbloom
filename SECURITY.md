# Security

## Reporting a vulnerability

Please open a [private security advisory](https://github.com/NNikolaG/diskbloom/security/advisories/new)
instead of a public issue. Include the macOS version, the Diskbloom version and steps to
reproduce.

## What Diskbloom can and cannot do

Diskbloom usually runs with **Full Disk Access**, so it is designed to be boring with that power:

- **No network access.** The app and the CLI contain no networking code. Nothing about your
  files leaves your Mac.
- **Reads metadata, not contents.** Scanning only reads file names and sizes (`lstat`). File
  contents are read only by the duplicate finder, to hash files of identical size locally.
- **Never follows symlinks**, neither while scanning nor while deleting.
- **Deletes only what you confirm.** Everything goes to the macOS Trash (you can put it back),
  except iOS simulators and simulator runtimes (`xcrun simctl delete`, `xcrun simctl runtime
  delete`) and Time Machine snapshots (`tmutil`, asks for your admin password). The Docker
  disk image is never deleted.
- **Conservative cleanup rules.** Project rules (`node_modules`, `target/`, …) never apply
  inside `node_modules`, `.app` bundles, `~/Library`, system folders or tool folders such as
  `~/.nvm`, `~/.vscode` or `~/.cargo`. Only regenerable categories are preselected.
- **Hardened runtime.** The app is signed with the hardened runtime, so other processes cannot
  inject code into it to borrow its Full Disk Access. The only entitlement is sending Apple
  Events to Finder (for "Empty Trash").
- **No telemetry.** The only thing the app stores is its last scan of each place (file
  names and sizes, in `~/Library/Caches/io.github.nnikolag.diskbloom/scans`), so it can
  show it right away next time and list what grew. It stays on your Mac; **Forget Saved
  Scans** in the File menu deletes it.

## Security review (v0.3.0)

Scope: Rust core, CLI, UniFFI bridge, SwiftUI app, build script and GitHub workflows.

The fixes below ship in **0.3.0**. The 0.2.0 download was built before them (for example
without the hardened runtime), so please update.

| # | Finding | Severity | Status |
|---|---|---|---|
| 1 | App was signed without the hardened runtime. A process could launch it with `DYLD_INSERT_LIBRARIES` and use its Full Disk Access. | High | Fixed: signed with `--options runtime`; CI verifies the flag. |
| 2 | Simulator folder names were passed to `xcrun simctl delete`. A folder named `all` would have deleted every simulator. | Medium | Fixed: only UUIDs are accepted. |
| 3 | Time Machine snapshot names from `tmutil` were inserted into a command run with admin rights. | Medium | Fixed: only the exact `YYYY-MM-DD-HHMMSS` format is accepted. |
| 4 | The project rules matched packages inside global npm / pnpm / yarn / bun installs, editor extensions and Electron apps. | Medium (data loss) | Fixed: protected locations, no descent into `node_modules`, tests. |
| 5 | Any folder named `DerivedData` was preselected for removal. | Medium (data loss) | Fixed: only Xcode's DerivedData location. |
| 6 | The Trash category tried to move `~/.Trash` itself to the Trash. | Low | Fixed: empties the Trash through Finder. |
| 7 | GitHub Actions referenced by mutable tags; CI token had default permissions. | Low (supply chain) | Fixed: actions pinned to commit SHAs, CI token read-only. |
| 8 | Release builds are not notarized, so users must bypass Gatekeeper once. | Low | Open: needs an Apple Developer account. Each release publishes `SHA256SUMS.txt`. |
| 9 | `basic-toml` (used only by the UniFFI code generator at build time) is unmaintained (RUSTSEC-2026-0374). | Info | Accepted: not reachable at runtime. |

Checked and found fine: no `unsafe` Rust; `cargo audit` reports no vulnerabilities; the CLI's
HTML map escapes file names (no script injection through crafted names); the CLI checks for
symlinks before deleting and uses `remove_dir_all`, which does not follow symlinks; external
tools are started with absolute paths and argument arrays (no shell), except the admin command
in #3, which now only receives validated values.
