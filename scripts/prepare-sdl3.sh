#!/bin/sh
# Downloads SDL's official, pinned Apple XCFramework for SwiftPM and xtool.
set -eu

VERSION=3.4.20
SHA256=36b7e4cefcf7d55d227b3df5e686f8f33ab34193173a976445d1b57c80009e44
URL="https://github.com/libsdl-org/SDL/releases/download/release-$VERSION/SDL3-$VERSION.dmg"
CDPATH=''
ROOT=$(cd -- "$(dirname "$0")/.." && pwd)
DEST="$ROOT/Vendor/SDL3.xcframework"
MARKER="$ROOT/Vendor/SDL3.version"

if [ -f "$DEST/Info.plist" ] && [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$VERSION $SHA256" ]; then
    echo "using $DEST from SDL $VERSION"
    exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/factorios-sdl3.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
ARCHIVE="$WORK/SDL3.dmg"
curl --fail --location --retry 3 --output "$ARCHIVE" "$URL"
ACTUAL=$(python3 -c 'import hashlib, pathlib, sys; print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())' "$ARCHIVE")
if [ "$ACTUAL" != "$SHA256" ]; then
    echo "SDL archive checksum mismatch: $ACTUAL" >&2
    exit 1
fi

7zz x -y "$ARCHIVE" 'SDL3/SDL3.xcframework/*' "-o$WORK/extracted" >/dev/null
mkdir -p "$ROOT/Vendor"
rm -rf "$DEST"
mv "$WORK/extracted/SDL3/SDL3.xcframework" "$DEST"
printf '%s %s\n' "$VERSION" "$SHA256" >"$MARKER"
echo "prepared $DEST from SDL $VERSION"
