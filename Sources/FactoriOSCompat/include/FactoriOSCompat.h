// The Mac-only API surface Factorio's own code reaches, rebuilt on UIKit, ImageIO and Metal for iOS.
//
// The converter records the pointer slots through which the game reaches each symbol in FOSCompatReplacements; the
// loader writes the replacement's address into those slots after dlopen. Everything here runs on a device only.

#pragma once

@import Foundation;
@import UIKit;

#import "FOSSDL.h"

NS_ASSUME_NONNULL_BEGIN

/// One symbol the game imports and what the loader points its slots at.
typedef struct {
    /// The Mach-O symbol name, with its leading underscore (`_NSApp`, `_OBJC_CLASS_$_NSBitmapImageRep`).
    const char *symbol;
    /// The replacement: a class object, a variable's address or a function's address.
    const void *replacement;
} FOSSymbolReplacement;

/// Every symbol the converter must record and the loader must point at a replacement.
///
/// The table lives for the process; `count` receives its length.
const FOSSymbolReplacement *FOSCompatReplacements(size_t *count);

/// Writes `value` into the pointer slot `slot` of a loaded image, making its page writable for the write and then
/// restoring the page's protection (vm_protect). Returns the Mach error, KERN_SUCCESS (0) when the slot holds `value`.
int FOSCompatWriteSlot(void *slot, const void *value);

/// Adapts Metal and Core Animation to the macOS behaviour the game expects. Call once, before the game starts.
///
/// Managed storage becomes shared storage; `didModifyRange:` and the blit encoder's `synchronize...` methods exist and
/// do nothing (Apple GPUs share memory with the CPU); `isLowPower` answers NO; `CAMetalLayer` accepts
/// `setDisplaySyncEnabled:`; `presentDrawable:` honours the frame-rate cap; `nextDrawable` waits while the app is in
/// the background, where iOS forbids GPU work.
void FOSCompatInstallMetalFixes(void);

/// Sets what `_NSGetExecutablePath` answers: the imported game's macOS executable rather than FactoriOS.
void FOSCompatSetExecutablePath(const char *path);

/// Sets what the game's `execv` (its self-restart) calls instead, on the main thread, with the requested arguments.
void FOSCompatSetRestartHandler(void (NS_SWIFT_SENDABLE ^handler)(NSArray<NSString *> *arguments));

/// Tells the frame gate whether the app is in the background; while it is, `nextDrawable` waits.
void FOSCompatSetBackgrounded(BOOL backgrounded);

/// Caps presented frames per second; 0 or less removes the cap.
void FOSCompatSetFrameRateCap(NSInteger framesPerSecond);

/// Number of frames submitted through `presentDrawable:` since the Metal compatibility hooks were installed.
/// The app-facing FPS counter samples this value; unlike Metal's developer HUD, it works on stock iOS.
uint64_t FOSCompatPresentedFrameCount(void);

/// Keeps `window` at `frame` (screen points), even if its class resets its frame during layout as SDL's window does.
void FOSCompatSetWindowFrame(UIWindow *window, CGRect frame);

NS_ASSUME_NONNULL_END
