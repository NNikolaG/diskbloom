#!/usr/bin/env bash
# Builds Diskbloom.app: Rust core -> static library -> Swift bindings -> SwiftUI app.
# Needs Rust (rustup or Homebrew) and the Xcode Command Line Tools; full Xcode is not needed.
#   ./build.sh              this Mac's architecture, release
#   ./build.sh --universal  arm64 + x86_64
#   ./build.sh --install    also replace /Applications/Diskbloom.app
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
BUILD="$PWD/build"
LIB=libdiskbloom_ffi

UNIVERSAL=0; INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --install)   INSTALL=1 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [[ $UNIVERSAL == 1 ]]; then
  TARGETS=(aarch64-apple-darwin x86_64-apple-darwin)
else
  case "$(uname -m)" in
    arm64) TARGETS=(aarch64-apple-darwin) ;;
    *)     TARGETS=(x86_64-apple-darwin) ;;
  esac
fi

# rustup is installed but this shell has not loaded ~/.cargo/env yet
[ -d "$HOME/.cargo/bin" ] && export PATH="$HOME/.cargo/bin:$PATH"
if ! command -v cargo >/dev/null; then
  echo "Rust is not installed. Install it and run this again:" >&2
  echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" >&2
  echo "  (or: brew install rust)" >&2
  exit 1
fi
if ! command -v swift >/dev/null; then
  echo "Xcode Command Line Tools are missing: xcode-select --install" >&2
  exit 1
fi

echo "==> Rust (${TARGETS[*]})"
export MACOSX_DEPLOYMENT_TARGET=13.0
OUTDIRS=()
if command -v rustup >/dev/null; then
  for t in "${TARGETS[@]}"; do
    rustup target add "$t" >/dev/null
    cargo build --manifest-path "$ROOT/Cargo.toml" -p diskbloom-ffi --release --target "$t"
    OUTDIRS+=("$ROOT/target/$t/release")
  done
else
  # Rust without rustup (e.g. Homebrew): only this Mac's architecture
  if [[ ${#TARGETS[@]} -gt 1 ]]; then
    echo "--universal needs rustup (https://rustup.rs)" >&2; exit 1
  fi
  cargo build --manifest-path "$ROOT/Cargo.toml" -p diskbloom-ffi --release
  OUTDIRS+=("$ROOT/target/release")
fi

rm -rf "$BUILD" && mkdir -p "$BUILD/ffi" "$BUILD/lib"
libs=(); for d in "${OUTDIRS[@]}"; do libs+=("$d/$LIB.a"); done
lipo -create "${libs[@]}" -output "$BUILD/lib/$LIB.a"

echo "==> Swift bindings (uniffi-bindgen)"
cargo run --manifest-path "$ROOT/Cargo.toml" -q -p diskbloom-ffi --bin uniffi-bindgen -- \
  generate --library "${OUTDIRS[0]}/$LIB.dylib" \
  --language swift --out-dir "$BUILD/gen"
cp "$BUILD/gen/diskbloom_ffiFFI.h" "$BUILD/ffi/"
cp "$BUILD/gen/diskbloom_ffiFFI.modulemap" "$BUILD/ffi/module.modulemap"
cp "$BUILD/gen/diskbloom_ffi.swift" Sources/DiskbloomFFI/diskbloom_ffi.swift

echo "==> SwiftUI app"
ARCHS=(); for t in "${TARGETS[@]}"; do ARCHS+=(--arch "${t%%-*}"); done
ARCHS=("${ARCHS[@]/aarch64/arm64}")
swift build -c release --product Diskbloom "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Diskbloom"

APP="$BUILD/Diskbloom.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Diskbloom"
cp Info.plist "$APP/Contents/Info.plist"
# Translations (English is the base language, Serbian in sr.lproj)
cp -R Resources/*.lproj "$APP/Contents/Resources/"
# Version from the git tag (v0.2.0 -> 0.2.0), if HEAD is tagged
if VERSION="$(git -C "$ROOT" describe --tags --exact-match 2>/dev/null)"; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION#v}" "$APP/Contents/Info.plist"
fi

# Icon: AppIcon.png (1024 px) -> .icns
ICONSET="$BUILD/AppIcon.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
# Sign with the hardened runtime (--options runtime): it blocks library injection
# (DYLD_INSERT_LIBRARIES and the like), so no other process can borrow the Full Disk
# Access the user gave Diskbloom. With a stable identity (the free "Apple Development"
# certificate from Xcode, or Developer ID) macOS keeps Full Disk Access across builds.
# An ad-hoc signature changes with every build, so macOS treats each build as a new app.
IDENTITY="${DISKBLOOM_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -Eo '"(Developer ID Application|Apple Development)[^"]*"' | head -1 | tr -d '"' || true)}"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --options runtime --entitlements Diskbloom.entitlements --sign "$IDENTITY" "$APP" >/dev/null
  echo "==> signed: $IDENTITY"
else
  codesign --force --options runtime --entitlements Diskbloom.entitlements --sign - "$APP" >/dev/null
  echo "==> ad-hoc signature (Full Disk Access must be granted again after each build)"
fi

if [[ $INSTALL == 1 ]]; then
  pkill -x Diskbloom 2>/dev/null && sleep 1 || true
  rm -rf /Applications/Diskbloom.app
  cp -R "$APP" /Applications/
  # No second copy in the build folder, or Spotlight shows two apps
  rm -rf "$APP"
  echo "==> installed: /Applications/Diskbloom.app"
  echo "    open -a Diskbloom"
else
  echo "==> done: $APP"
  echo "    open \"$APP\""
fi
