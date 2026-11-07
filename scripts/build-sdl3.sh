#!/bin/sh
# Builds SDL3 for iOS devices as Vendor/SDL3.xcframework, which Package.swift picks up and xtool embeds in
# FactoriOS.app/Frameworks. The game's own (static, macOS) SDL3 forwards every call to it through SDL3_DYNAMIC_API.
# Needs macOS with Xcode, CMake and git:  mise run sdl3
set -eu
SDL_TAG=release-3.4.20
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${TMPDIR:-/tmp}/factorios-sdl3
rm -rf "$WORK" "$ROOT/Vendor/SDL3.xcframework"
mkdir -p "$WORK" "$ROOT/Vendor"

git clone --quiet --depth 1 --branch "$SDL_TAG" https://github.com/libsdl-org/SDL.git "$WORK/src"
cmake -S "$WORK/src" -B "$WORK/build" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_FRAMEWORK=ON \
    -DSDL_TEST_LIBRARY=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF
cmake --build "$WORK/build" --config Release -- -sdk iphoneos CODE_SIGNING_ALLOWED=NO

framework=$(find "$WORK/build" -path '*Release-iphoneos/SDL3.framework' -type d | head -n 1)
xcodebuild -create-xcframework -framework "$framework" -output "$ROOT/Vendor/SDL3.xcframework"
echo "built $ROOT/Vendor/SDL3.xcframework from SDL $SDL_TAG"
