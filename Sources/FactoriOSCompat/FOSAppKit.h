// The Mac-only AppKit and Foundation classes Factorio's own code uses, rebuilt on ImageIO, CoreGraphics and UIKit.
// The loader points the game's class references for NSAppleEventManager, NSBitmapImageRep, NSColorSpace and
// NSWorkspace at these classes, so they answer exactly the selectors the game sends (docs/feasibility.md lists them).

#ifndef FACTORIOS_FOS_APP_KIT_H
#define FACTORIOS_FOS_APP_KIT_H

@import CoreGraphics;
@import Foundation;

NS_ASSUME_NONNULL_BEGIN

/// NSColorSpace on a CGColorSpace.
@interface FOSColorSpace : NSObject

/// The sRGB color space; the same object on every call, as AppKit's is.
+ (FOSColorSpace *)sRGBColorSpace;

/// The uncalibrated RGB color space; the same object on every call.
+ (FOSColorSpace *)genericRGBColorSpace;

/// Wraps `space`, retaining it.
- (instancetype)initWithCGColorSpace:(CGColorSpaceRef)space NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/// The wrapped CoreGraphics color space, valid as long as the receiver.
- (CGColorSpaceRef)CGColorSpace;

@end

/// NSBitmapImageRep for the game's image loading: 8-bit RGBA, non-premultiplied, rows packed.
@interface FOSBitmapImageRep : NSObject

/// Decodes the first image in `data` (PNG, JPEG or anything ImageIO reads); nil when it can't.
+ (nullable FOSBitmapImageRep *)imageRepWithData:(NSData *)data;

- (instancetype)init NS_UNAVAILABLE;

/// The pixels: `pixelsHigh` rows of `pixelsWide` RGBA quadruplets.
- (unsigned char *)bitmapData NS_RETURNS_INNER_POINTER;

/// Always 32.
- (NSInteger)bitsPerPixel;

/// Always 4: red, green, blue, alpha.
- (NSInteger)samplesPerPixel;

/// The height in pixels.
- (NSInteger)pixelsHigh;

/// The width in pixels.
- (NSInteger)pixelsWide;

/// The color space the pixel values are in.
- (FOSColorSpace *)colorSpace;

/// The same image with its colors converted into `space`.
- (nullable FOSBitmapImageRep *)bitmapImageRepByConvertingToColorSpace:(FOSColorSpace *)space
                                                       renderingIntent:(NSInteger)intent;

/// The same pixel values, tagged as being in `space`.
- (nullable FOSBitmapImageRep *)bitmapImageRepByRetaggingWithColorSpace:(FOSColorSpace *)space;

@end

/// NSAppleEventManager: iOS has no Apple Events, so the game's URL-handler registration is ignored.
@interface FOSAppleEventManager : NSObject

/// The shared manager; the same object on every call.
+ (FOSAppleEventManager *)sharedAppleEventManager;

/// Ignores a URL handler: the game's SDL code registers one for `kInternetEventClass`/`kAEGetURL`.
- (void)setEventHandler:(nullable id)handler
            andSelector:(SEL)selector
          forEventClass:(uint32_t)eventClass
             andEventID:(uint32_t)eventID;

/// Ignores a handler removal; there was nothing to remove.
- (void)removeEventHandlerForEventClass:(uint32_t)eventClass andEventID:(uint32_t)eventID;

@end

/// NSWorkspace: shows folders in the Files app.
@interface FOSWorkspace : NSObject

/// The shared workspace.
+ (FOSWorkspace *)sharedWorkspace;

/// Opens the folder of the first URL (or the URL itself when it is a folder) in the Files app.
- (void)activateFileViewerSelectingURLs:(NSArray<NSURL *> *)fileURLs;

@end

NS_ASSUME_NONNULL_END

#endif  // FACTORIOS_FOS_APP_KIT_H
