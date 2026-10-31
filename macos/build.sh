#!/usr/bin/env bash
# Pravi Diskbloom.app: Rust jezgro -> xcframework -> Swift veze -> SwiftUI app.
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

echo "==> Rust (${TARGETS[*]})"
export MACOSX_DEPLOYMENT_TARGET=13.0
for t in "${TARGETS[@]}"; do
  rustup target add "$t" >/dev/null
  cargo build --manifest-path "$ROOT/Cargo.toml" -p diskbloom-ffi --release --target "$t"
done

rm -rf "$BUILD" && mkdir -p "$BUILD/headers" "$BUILD/lib"
libs=(); for t in "${TARGETS[@]}"; do libs+=("$ROOT/target/$t/release/$LIB.a"); done
lipo -create "${libs[@]}" -output "$BUILD/lib/$LIB.a"

echo "==> Swift veze (uniffi-bindgen)"
cargo run --manifest-path "$ROOT/Cargo.toml" -q -p diskbloom-ffi --bin uniffi-bindgen -- \
  generate --library "$ROOT/target/${TARGETS[0]}/release/$LIB.dylib" \
  --language swift --out-dir "$BUILD/gen"
cp "$BUILD/gen/diskbloom_ffiFFI.h" "$BUILD/headers/"
cp "$BUILD/gen/diskbloom_ffiFFI.modulemap" "$BUILD/headers/module.modulemap"
cp "$BUILD/gen/diskbloom_ffi.swift" Sources/DiskbloomFFI/diskbloom_ffi.swift

echo "==> xcframework"
xcodebuild -create-xcframework -library "$BUILD/lib/$LIB.a" -headers "$BUILD/headers" \
  -output "$BUILD/diskbloom_ffiFFI.xcframework" >/dev/null

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
