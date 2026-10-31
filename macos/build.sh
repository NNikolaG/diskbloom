#!/usr/bin/env bash
# Pravi Diskbloom.app: Rust jezgro -> staticka biblioteka -> Swift veze -> SwiftUI app.
# Treba: Rust (rustup ili brew) i Xcode Command Line Tools. Pun Xcode nije potreban.
#   ./build.sh              arhitektura ovog Mac-a, release
#   ./build.sh --universal  arm64 + x86_64
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
BUILD="$PWD/build"
LIB=libdiskbloom_ffi

if [[ "${1:-}" == "--universal" ]]; then
  TARGETS=(aarch64-apple-darwin x86_64-apple-darwin)
else
  case "$(uname -m)" in
    arm64) TARGETS=(aarch64-apple-darwin) ;;
    *)     TARGETS=(x86_64-apple-darwin) ;;
  esac
fi

# rustup instaliran, ali shell jos nije ucitao ~/.cargo/env
[ -d "$HOME/.cargo/bin" ] && export PATH="$HOME/.cargo/bin:$PATH"
if ! command -v cargo >/dev/null; then
  echo "Rust nije instaliran. Instaliraj ga pa pokreni ponovo:" >&2
  echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" >&2
  echo "  (ili: brew install rust)" >&2
  exit 1
fi
if ! command -v swift >/dev/null; then
  echo "Nedostaju Xcode Command Line Tools: xcode-select --install" >&2
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
  # Rust bez rustup-a (npr. Homebrew): samo arhitektura ovog Mac-a
  if [[ ${#TARGETS[@]} -gt 1 ]]; then
    echo "--universal zahteva rustup (https://rustup.rs)" >&2; exit 1
  fi
  cargo build --manifest-path "$ROOT/Cargo.toml" -p diskbloom-ffi --release
  OUTDIRS+=("$ROOT/target/release")
fi

rm -rf "$BUILD" && mkdir -p "$BUILD/ffi" "$BUILD/lib"
libs=(); for d in "${OUTDIRS[@]}"; do libs+=("$d/$LIB.a"); done
lipo -create "${libs[@]}" -output "$BUILD/lib/$LIB.a"

echo "==> Swift veze (uniffi-bindgen)"
cargo run --manifest-path "$ROOT/Cargo.toml" -q -p diskbloom-ffi --bin uniffi-bindgen -- \
  generate --library "${OUTDIRS[0]}/$LIB.dylib" \
  --language swift --out-dir "$BUILD/gen"
cp "$BUILD/gen/diskbloom_ffiFFI.h" "$BUILD/ffi/"
cp "$BUILD/gen/diskbloom_ffiFFI.modulemap" "$BUILD/ffi/module.modulemap"
cp "$BUILD/gen/diskbloom_ffi.swift" Sources/DiskbloomFFI/diskbloom_ffi.swift

echo "==> SwiftUI app"
ARCHS=(); for t in "${TARGETS[@]}"; do ARCHS+=(--arch "${t%%-*}"); done
ARCHS=("${ARCHS[@]/aarch64/arm64}")
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Diskbloom"

APP="$BUILD/Diskbloom.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Diskbloom"
cp Info.plist "$APP/Contents/Info.plist"

# Ikonica: AppIcon.png (1024) -> .icns
ICONSET="$BUILD/AppIcon.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null  # ad-hoc potpis; za distribuciju treba Developer ID
echo "==> gotovo: $APP"
echo "    open \"$APP\""
