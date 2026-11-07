#!/bin/sh
# Builds SDL3 for iOS devices as Vendor/SDL3.xcframework, which Package.swift picks up and xtool embeds in
# FactoriOS.app/Frameworks. The game's own (static, macOS) SDL3 forwards every call to it through SDL3_DYNAMIC_API.
# Needs macOS with Xcode, CMake and git:  mise run sdl3
set -eu
SDL_TAG=release-3.4.20
SDL_COMMIT=f00dc919ca35b9756316e86c4777392de442f9b2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${TMPDIR:-/tmp}/factorios-sdl3
rm -rf "$WORK" "$ROOT/Vendor/SDL3.xcframework"
mkdir -p "$WORK" "$ROOT/Vendor"

git init --quiet "$WORK/src"
git -C "$WORK/src" remote add origin https://github.com/libsdl-org/SDL.git
git -C "$WORK/src" fetch --quiet --depth 1 origin "$SDL_COMMIT"
test "$(git -C "$WORK/src" rev-parse FETCH_HEAD)" = "$SDL_COMMIT"
git -C "$WORK/src" checkout --quiet --detach FETCH_HEAD
cmake -S "$WORK/src" -B "$WORK/build" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_FRAMEWORK=ON \
    -DSDL_TEST_LIBRARY=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF
cmake --build "$WORK/build" --config Release -- -sdk iphoneos CODE_SIGNING_ALLOWED=NO

framework=$(find "$WORK/build" -path '*Release-iphoneos/SDL3.framework' -type d | head -n 1)
xcodebuild -create-xcframework -framework "$framework" -output "$ROOT/Vendor/SDL3.xcframework"
echo "built $ROOT/Vendor/SDL3.xcframework from SDL $SDL_TAG ($SDL_COMMIT)"
