# Contributing

Thanks for helping. Diskbloom deletes files, so changes that touch cleanup rules or
removal need a test that shows what is *not* removed as well as what is.

## Checks

Everything CI runs, in order:

```bash
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
./macos/build.sh
(cd macos && swift test)
```

The Rust checks also run on Linux. The app and `swift test` need macOS with the Xcode
Command Line Tools.

## Rust (`crates/`)

- Clippy's pedantic group is on for the whole workspace (see `Cargo.toml`); fix
  warnings rather than silencing them. When an `allow` is right, say why in a comment.
- No `unsafe` (forbidden by the workspace lints), no `unwrap`/`expect` outside tests.
- Public items have doc comments; fallible functions document `# Errors`.
- New Smart Clean targets go in `crates/core/src/clean/rules.rs`. A new category also
  needs an entry in `Category` (`clean/category.rs`), in `CategoryInfo` on the Swift
  side and in the README table.

## Swift (`macos/`)

- Deployment target is macOS 13; check availability before using newer APIs.
- Swift 6 language mode. Long work runs off the main actor (`Task.detached`), UI state
  stays on `@MainActor`.
- One type per file, in the folder of the feature it belongs to. Logic that needs no
  UI goes in `DiskbloomKit` with a test.
- User-facing text is English and must have a Serbian translation in
  `macos/Resources/sr.lproj/Localizable.strings` (the key is the English text;
  interpolated values become `%@`).
- Icon-only buttons need an accessibility label (`IconButton` does this).

## Commits and pull requests

- One logical change per commit, with a message that says what and why.
- Pull requests run the full CI, including screenshots of the app
  (`screenshots` artifact) so UI changes can be checked without building.

The guidelines in `.claude/skills` (Rust best practices, SwiftUI, Swift concurrency)
apply too; where they conflict with this file, this file wins.
