#!/bin/sh
# Builds SDL3's Apple XCFramework for iOS devices and the simulator from SDL's pinned release source, with the dynamic
# API turned on. SDL's official iOS framework compiles the dynamic API out, so the game's static SDL3 couldn't forward
# to it through SDL3_DYNAMIC_API and would run its own macOS (Cocoa) backend instead.
set -eu

VERSION=3.4.20
SHA256=f3bb06f55bed9557227a700af2ea62e49497ebdf58037732a731a5fb3ef8581f
URL="https://github.com/libsdl-org/SDL/releases/download/release-$VERSION/SDL3-$VERSION.tar.gz"
# Bumped whenever the build below changes, so an earlier Vendor/SDL3.xcframework is rebuilt.
RECIPE=dynapi-ios-1
CDPATH=''
ROOT=$(cd -- "$(dirname "$0")/.." && pwd)
DEST="$ROOT/Vendor/SDL3.xcframework"
MARKER="$ROOT/Vendor/SDL3.version"
STAMP="$VERSION $SHA256 $RECIPE"

if [ -f "$DEST/Info.plist" ] && [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$STAMP" ]; then
    echo "using $DEST from SDL $VERSION"
    exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/factorios-sdl3.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
ARCHIVE="$WORK/SDL3.tar.gz"
curl --fail --location --retry 3 --output "$ARCHIVE" "$URL"
ACTUAL=$(shasum -a 256 "$ARCHIVE" | cut -d ' ' -f 1)
if [ "$ACTUAL" != "$SHA256" ]; then
    echo "SDL archive checksum mismatch: $ACTUAL" >&2
    exit 1
fi
tar -xzf "$ARCHIVE" -C "$WORK"
SOURCE="$WORK/SDL3-$VERSION"

# SDL_dynapi.h is the only switch for the dynamic API; SDL rejects a command-line define on purpose.
python3 - "$SOURCE/src/dynapi/SDL_dynapi.h" <<'EOF'
import pathlib, sys
header = pathlib.Path(sys.argv[1])
off = "#elif defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE // probably not useful on iOS.\n#define SDL_DYNAMIC_API 0\n"
on = "#elif defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE // FactoriOS: the game's static SDL3 forwards here.\n#define SDL_DYNAMIC_API 1\n"
text = header.read_text()
if text.count(off) != 1:
    sys.exit(f"{header} no longer has the iOS dynamic API switch; update scripts/prepare-sdl3.sh")
header.write_text(text.replace(off, on))
EOF
# The vendor string SDL's own release build sets.
cp "$SOURCE/Xcode/SDL/pkg-support/build.xcconfig" "$SOURCE/Xcode/SDL/build.xcconfig"

archive() {
    # IPHONEOS_DEPLOYMENT_TARGET matches Package.swift; SDL's project still says 11.0, which Xcode no longer builds.
    # The .metal sources only produce a default.metallib that SDL never loads (its renderer and GPU backend embed
    # precompiled shaders), and compiling them needs Xcode's separately downloaded Metal Toolchain.
    xcodebuild archive -quiet \
        -project "$SOURCE/Xcode/SDL/SDL.xcodeproj" -scheme SDL3 -configuration Release \
        -destination "generic/platform=$1" -archivePath "$WORK/$2.xcarchive" -derivedDataPath "$WORK/DerivedData" \
        ONLY_ACTIVE_ARCH=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO CODE_SIGNING_ALLOWED=NO \
        IPHONEOS_DEPLOYMENT_TARGET=17.0 EXCLUDED_SOURCE_FILE_NAMES='*.metal'
}
archive iOS iphoneos
archive 'iOS Simulator' iphonesimulator

FRAMEWORK=Products/Library/Frameworks/SDL3.framework
xcodebuild -create-xcframework \
    -framework "$WORK/iphoneos.xcarchive/$FRAMEWORK" \
    -framework "$WORK/iphonesimulator.xcarchive/$FRAMEWORK" \
    -output "$WORK/SDL3.xcframework" >/dev/null
mkdir -p "$ROOT/Vendor"
rm -rf "$DEST"
mv "$WORK/SDL3.xcframework" "$DEST"
printf '%s\n' "$STAMP" >"$MARKER"
echo "prepared $DEST from SDL $VERSION source with the dynamic API"
