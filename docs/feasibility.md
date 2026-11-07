# Feasibility: Factorio's macOS build on iOS

Evidence comes from `artifact/factorio-demo_mac_2.1.23.dmg` (Factorio demo 2.1.23), read with 7-Zip and
`scripts/inspect-binary` (LIEF plus a small ARM64 cross-referencer). Everything quoted below is that script's output or a
7-Zip listing. Conclusions that rest on knowledge of iOS rather than on the binary are marked **[inference]**.

**Verdict: no blocker found in the binary; four gates remain that only a device can close.** The game's own code
reaches a handful of Mac-only APIs. For most of them iOS has a counterpart; for the rest (OpenCL, process restart,
`fork`, display sync) the honest iOS behaviour is "not available", which the game already handles. Everything else
that is Mac-only belongs to the statically linked SDL3, which the game hands over to an iOS build of SDL3 through
SDL's dynamic API. The gates are listed at the end.

## The disk image

UDIF (`koly` trailer), partition map with one `Apple_HFS` partition. Chunk types in the `blkx` tables:

```
Counter({'0x80000006': 2472, '0xffffffff': 9, '0x2': 5})
```

`0x80000006` is bzip2, `0x2` is "ignore", `0xffffffff` ends a table. The volume is HFS+ and uses hard links
(`Factorio/[HFS+ Private Data]` is in the listing). Apple's Compression framework has no bzip2, so the importer carries
its own decoder.

```
Factorio/factorio.app/Contents/MacOS/factorio            226401616
Factorio/factorio.app/Contents/MacOS/factorio.dSYM/...   (symbols for both slices)
Factorio/factorio.app/Contents/data/core/graphics/shaders/*.metal   110 files
Factorio/factorio.app/Contents/Info.plist                CFBundleIdentifier com.factorio, LSMinimumSystemVersion 10.13
```

Shaders ship as Metal **source**, which iOS compiles at run time (`newLibraryWithSource` is in the binary). No
macOS-targeted `.metallib` has to be translated.

## The executable

Universal (`x86_64` + `arm64`). The arm64 slice:

```
filetype=EXECUTE flags=['NOUNDEFS', 'DYLDLINK', 'TWOLEVEL', 'WEAK_DEFINES', 'BINDS_TO_WEAK', 'PIE', 'HAS_TLV_DESCRIPTORS']
sizeofcmds=6000 first section at 0x8800: 28784 bytes free
SEGMENT_64             __PAGEZERO vm=0x0+0x100000000
DYLD_INFO_ONLY
BUILD_VERSION          MACOS minos=[11, 0, 0] sdk=[11, 0, 0]
MAIN
LOAD_DYLIB             .../AppKit.framework/Versions/C/AppKit   (and 26 more, Cocoa, Carbon, IOKit, OpenGL, OpenCL, LDAP ...)
CODE_SIGNATURE
```

What that means for the converter:

- **Classic bind opcodes** (`DYLD_INFO_ONLY`), not chained fixups. Setting a bind's weak-import flag
  (`BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM`) only changes an immediate, so the converter makes imports from
  frameworks iOS lacks or trims weak without moving any of `__LINKEDIT`.
- **28 KB free after the load commands**: room to rebuild the command list (add `LC_ID_DYLIB`, drop `LC_LOAD_DYLINKER`).
- **A 4 GB `__PAGEZERO`** has to shrink before the image can be `dlopen`ed as a library, as LiveContainer does.
- **Framework paths** are macOS's versioned ones (`Versions/A/`); iOS frameworks are flat, so every path is rewritten.
- The full symbol table is present (1,088,708 symbols), so functions have names in the evidence below.

## Mac-only APIs the game itself reaches

`inspect-binary` attributes every reference to an import to the function that makes it, then sets aside functions of
the static SDL3 (they never run once SDL is redirected). What remains:

```
AppKit: 60 imports, 4 reached by game code
  _NSApp <- __Z32setup_macos_application_menu_barv, __Z37remove_close_window_keyboard_shortcutv
  _OBJC_CLASS_$_NSBitmapImageRep <- __Z13preload_imagePcmbR11PreloadData
  _OBJC_CLASS_$_NSColorSpace <- __Z18maybeConvertToSRGBPKhmP16NSBitmapImageRep
  _OBJC_CLASS_$_NSWorkspace <- __ZN10SystemUtil28openFileManagerAndSelectFileERKN10Filesystem4PathE
ApplicationServices: 1 imports, 1 reached by game code
  _UAZoomEnabled <- __ZN10SystemUtil26isAccessibilityZoomEnabledEv
Carbon: 5 imports, 0 reached by game code
CoreServices: 11 imports, 0 reached by game code
CoreVideo: 22 imports, 0 reached by game code
ForceFeedback: 13 imports, 0 reached by game code
IOKit: 58 imports, 1 reached by game code
  _IOPMAssertionRelease <- __ZN10SystemUtil12preventSleepEv
LDAP: 18 imports, 0 reached by game code
Metal: ... _MTLCopyAllDevicesWithObserver <- MTL::CopyAllDevicesWithObserver(...)
OpenCL: 3 imports, 3 reached by game code
  _clGetDeviceIDs / _clGetDeviceInfo / _clGetPlatformIDs <- GPUDetectionOpenGL::createGPUListUsingOpenCL()
```

Selectors those functions send (from `__objc_selrefs`):

```
preload_image:        bitmapData bitsPerPixel bytes drain imageRepWithData: initWithBytesNoCopy:length:freeWhenDone:
                      pixelsHigh pixelsWide samplesPerPixel
maybeConvertToSRGB:   bitmapImageRepByConvertingToColorSpace:renderingIntent: bitmapImageRepByRetaggingWithColorSpace:
                      colorSpace genericRGBColorSpace sRGBColorSpace
setup_macos_application_menu_bar, remove_close_window_keyboard_shortcut:  itemWithTitle: setKeyEquivalent: windowsMenu
SystemUtil::openFileManagerAndSelectFile:  activateFileViewerSelectingURLs: fileURLWithPath:isDirectory: sharedWorkspace
```

**The image decoder is the critical one:** the game loads its PNG sprites through `NSBitmapImageRep`. The compatibility
layer provides that class (and `NSColorSpace`) on ImageIO/CoreGraphics.

## Process control

```
_execv <- AppManager::restartApp(...), SystemUtil::runProcessDontWait(...)
_fork <- ChildProcessAgent::fork(...), SystemUtil::runProcessDontWait(...)   (and SDL)
__NSGetExecutablePath <- SystemUtil::getExecutablePath(...)
_dlopen <- _SDL_InitDynamicAPI, ...
```

iOS apps can neither `exec` nor `fork` **[inference: sandbox policy]**. The game restarts itself through `execv`
(after mod changes, for example); FactoriOS records the request, ends the session and asks the player to reopen the app.
`fork` fails with `ENOSYS`, which the game already handles as a failed child process **[inference]**.
`_NSGetExecutablePath` answers with the imported game's path, not FactoriOS's.

`Paths::getSystemReadData` asks `CFBundleGetMainBundle` for the game's data directory, which on iOS is FactoriOS's
bundle; `config.ini` (`read-data=`) points the game at the imported copy instead, as the Android launcher already did.

## Code that runs while the library loads

`dlopen` runs a library's static initializers and `+load` methods before it returns, which is before FactoriOS fills
the compatibility slots. So none of that code may reach a Mac-only or replaced import:

```
__objc_nlclslist (+load): 0 entries
__objc_nlcatlist (+load): 0 entries
__mod_init_func: 448 initializers; imports reached three calls deep: 73
  from Mac-only libraries or replaced by FactoriOS: none
  other libraries reached: CoreGraphics, Foundation, Metal, QuartzCore
```

What they do reach from those four libraries are constants iOS has (`kCGColorSpaceSRGB`, `kCAFilter*`, the
`MTLCommonCounter*` names, Foundation's error keys), so filling the slots right after `dlopen` and before the entry
point is early enough. The report is part of `scripts/inspect-binary`, to be checked again on every new game version.

## Metal on iOS

`metal-cpp` selectors that are macOS-only or behave differently on iOS, and the game code that uses them:

```
setDisplaySyncEnabled_: GraphicsInterfaceMetal::setVsync(bool)
didModifyRange_: ColorBitmapMetal::updateMipmapPixels, StagingBitmapMetal::unmap, UniformBufferMetal::updateBuffer, ...
synchronizeResource_: MetalFrameCounters::endFrame, StagingBitmapMetal::copyFrom, ColorBitmapMetal::copyDataRawInternal
synchronizeTexture_slice_level_: ColorBitmapMetal::generateMipmaps, ...
isLowPower, recommendedMaxWorkingSetSize, hasUnifiedMemory: GPUDetectionMetal::getGPUInfo
supportsBCTextureCompression: GraphicsInterfaceMetal::resolveMetalDeviceCapabilities
```

`didModifyRange:` and `synchronize*` belong to `MTLStorageModeManaged`, which iOS doesn't have. Apple GPUs share memory
with the CPU, so on iOS these have nothing to do: the compatibility layer adds them as empty operations on the concrete
Metal classes, and turns any request for managed storage into shared storage. `setDisplaySyncEnabled:` has no iOS
counterpart (iOS always presents in sync with the display). `supportsBCTextureCompression` is real on iOS 16.4+, and
the game reads it, so it falls back to uncompressed sprites where BC isn't supported **[inference]**.

## SDL

```
SDL3_DYNAMIC_API: 6 occurrence(s)
```

The game links SDL3 statically with the dynamic API left on. Setting `SDL3_DYNAMIC_API` to an iOS build of SDL3 routes
every SDL call to it: window and `CAMetalLayer` (UIKit), touch, audio (CoreAudio/AVAudioSession), game controllers
(GameController) and haptics. The static SDL's Cocoa, IOKit HID, ForceFeedback and CoreVideo code is never run.

On iOS, SDL expects to own the app's start-up. From SDL's source (`src/SDL.c`, `src/video/uikit/SDL_uikitappdelegate.m`,
main branch, read 2026-11-07):

```
#ifdef SDL_MAIN_NEEDED
static bool SDL_MainIsReady = false;          // SDL_Init fails until SDL_SetMainReady() or SDL_RunApp()
...
- (void)postFinishLaunch
    SDL_SetiOSEventPump(true);                 // not exported: only SDL's own delegate can turn the pump on
    exit_status = SDL_CallMainFunction(forward_argc, forward_argv, forward_main);
```

So FactoriOS starts through `SDL_RunApp` with its own main function. SDL's delegate then calls it with the event pump
on; it shows the launcher, and when the player starts a game it calls the game's entry point from there.

## LiveContainer's precedent

LiveContainer runs unmodified iOS apps inside one sideloaded app. Its `LiveContainer/LCMachOUtils.m` (main branch,
read 2026-11-07) turns an executable into a library the same way FactoriOS has to:

```
header->filetype = MH_DYLIB;
header->flags |= MH_NO_REEXPORTED_DYLIBS;
header->flags &= ~MH_PIE;
// Patch __PAGEZERO to map just a single zero page, fixing "out of address space"
    seg->vmaddr = 0x100000000 - 0x4000;
    seg->vmsize = 0x4000;
// Make this the first load command on the list (like dylibify does) ... insertDylibCommand(LC_ID_DYLIB, ...)
```

Its README: "(Below iOS 26) When JIT is available, codesign is entirely bypassed ... Otherwise, your app will be signed
with the same certificate used by LiveContainer", and "In JIT-less mode, all executables are signed". That's the mode
FactoriOS uses: no JIT, every converted library signed on the device with the sideloading certificate. LiveContainer's
guests are iOS binaries; FactoriOS's is a macOS binary retagged for iOS (`LC_BUILD_VERSION`), which dyld otherwise
refuses to load into an iOS process **[inference]**.

## Gates only a device can close

1. **Sign and load.** A 226 MB library converted and signed on the device with a free Apple ID's certificate passes
   library validation and `dlopen`s. LiveContainer's JIT-less mode is the precedent; the macOS-to-iOS retag is new.
2. **SDL hand-over and lifecycle.** The game's static SDL3 forwards to FactoriOS's SDL3, and the UIKit window, Metal
   layer, touch and audio work when the game's entry point runs inside SDL's `postFinishLaunch`.
3. **Metal.** The 110 shaders compile on iOS's Metal compiler, and the game renders with managed storage turned into
   shared storage and without BC textures where the GPU lacks them.
4. **Memory and CPU.** The demo fits in the device's per-app memory limit (about 3 GB expected; the
   increased-memory-limit entitlement is requested where the signing team allows it), and the arm64 slice, built for
   Apple silicon Macs, runs on the device's CPU (A14 or later expected) **[inference]**.

iOS forbids GPU work in the background; the compatibility layer holds the game's next frame until the app is back in
the foreground.
