#import "FOSAppKit.h"

@import ImageIO;

#pragma mark - Color space

@implementation FOSColorSpace {
    CGColorSpaceRef _space;
}

+ (FOSColorSpace *)sRGBColorSpace {
    static FOSColorSpace *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        shared = [[FOSColorSpace alloc] initWithCGColorSpace:space];
        CGColorSpaceRelease(space);
    });
    return shared;
}

+ (FOSColorSpace *)genericRGBColorSpace {
    static FOSColorSpace *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // macOS's Generic RGB profile has no public iOS counterpart; device RGB is iOS's uncalibrated RGB space,
        // which is what the game's untagged images are in.
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        shared = [[FOSColorSpace alloc] initWithCGColorSpace:space];
        CGColorSpaceRelease(space);
    });
    return shared;
}

- (instancetype)initWithCGColorSpace:(CGColorSpaceRef)space {
    self = [super init];
    if (self != nil) {
        _space = CGColorSpaceRetain(space);
    }
    return self;
}

- (void)dealloc {
    CGColorSpaceRelease(_space);
}

- (CGColorSpaceRef)CGColorSpace {
    return _space;
}

@end

#pragma mark - Pixel helpers

/// The color space object for a decoded image's space: the shared sRGB one when it is sRGB.
static FOSColorSpace *FOSColorSpaceFor(CGColorSpaceRef space) {
    CFStringRef name = CGColorSpaceCopyName(space);
    BOOL isSRGB = name != NULL && CFEqual(name, kCGColorSpaceSRGB);
    if (name != NULL) {
        CFRelease(name);
    }
    return isSRGB ? [FOSColorSpace sRGBColorSpace] : [[FOSColorSpace alloc] initWithCGColorSpace:space];
}

/// The byte count of a packed RGBA8 image, or 0 when it is empty or too large.
static size_t FOSPackedLength(size_t width, size_t height) {
    size_t pixels = 0;
    size_t bytes = 0;
    if (width == 0 || height == 0 || __builtin_mul_overflow(width, height, &pixels) ||
        __builtin_mul_overflow(pixels, (size_t)4, &bytes)) {
        return 0;
    }
    return bytes;
}

/// Whether `image` already stores 8-bit RGB with straight (or no) alpha last, in big-endian byte order.
static BOOL FOSIsStraightRGBA8(CGImageRef image) {
    CGColorSpaceRef space = CGImageGetColorSpace(image);
    CGBitmapInfo info = CGImageGetBitmapInfo(image);
    CGImageAlphaInfo alpha = (CGImageAlphaInfo)(info & kCGBitmapAlphaInfoMask);
    CGBitmapInfo order = info & kCGBitmapByteOrderMask;
    BOOL bigEndian = order == kCGBitmapByteOrderDefault || order == kCGBitmapByteOrder32Big;
    BOOL straight = alpha == kCGImageAlphaLast || alpha == kCGImageAlphaNoneSkipLast;
    return space != NULL && CGColorSpaceGetModel(space) == kCGColorSpaceModelRGB &&
           CGImageGetBitsPerComponent(image) == 8 && CGImageGetBitsPerPixel(image) == 32 &&
           (info & kCGBitmapFloatComponents) == 0 && bigEndian && straight;
}

/// Copies the pixels of a straight-RGBA8 image as they are, packing rows; nil when the data is short.
static NSMutableData *_Nullable FOSCopyStraightRGBA8(CGImageRef image) {
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    size_t length = FOSPackedLength(width, height);
    size_t stride = CGImageGetBytesPerRow(image);
    CFDataRef source = length > 0 ? CGDataProviderCopyData(CGImageGetDataProvider(image)) : NULL;
    if (source == NULL) {
        return nil;
    }
    size_t rowLength = width * 4;
    size_t sourceLength = (size_t)CFDataGetLength(source);
    if (stride < rowLength || sourceLength < stride * (height - 1) + rowLength) {
        CFRelease(source);
        return nil;
    }
    NSMutableData *pixels = [NSMutableData dataWithLength:length];
    const uint8_t *from = CFDataGetBytePtr(source);
    uint8_t *to = pixels.mutableBytes;
    for (size_t row = 0; row < height; row++) {
        memcpy(to + row * rowLength, from + row * stride, rowLength);
    }
    CFRelease(source);
    CGImageAlphaInfo alpha = (CGImageAlphaInfo)(CGImageGetBitmapInfo(image) & kCGBitmapAlphaInfoMask);
    if (alpha == kCGImageAlphaNoneSkipLast) {
        for (size_t offset = 3; offset < length; offset += 4) {
            to[offset] = UINT8_MAX;
        }
    }
    return pixels;
}

/// Turns premultiplied RGBA8 into straight RGBA8 in place.
static void FOSUnpremultiply(uint8_t *pixels, size_t length) {
    for (size_t offset = 0; offset + 3 < length; offset += 4) {
        unsigned alpha = pixels[offset + 3];
        if (alpha == 0 || alpha == UINT8_MAX) {
            continue;
        }
        for (size_t channel = 0; channel < 3; channel++) {
            unsigned value = (pixels[offset + channel] * 255u + alpha / 2u) / alpha;
            pixels[offset + channel] = (uint8_t)(value > 255u ? 255u : value);
        }
    }
}

/// Draws `image` into straight RGBA8 in `space` (an RGB space). CoreGraphics only draws premultiplied, so the result
/// is premultiplied first and then divided back out.
static NSMutableData *_Nullable FOSRenderRGBA8(CGImageRef image, CGColorSpaceRef space, CGColorRenderingIntent intent) {
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    size_t length = FOSPackedLength(width, height);
    if (length == 0) {
        return nil;
    }
    NSMutableData *pixels = [NSMutableData dataWithLength:length];
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8, width * 4, space,
                                                 (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    if (context == NULL) {
        return nil;
    }
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextSetRenderingIntent(context, intent);
    CGContextDrawImage(context, CGRectMake(0, 0, (CGFloat)width, (CGFloat)height), image);
    CGContextRelease(context);
    FOSUnpremultiply(pixels.mutableBytes, length);
    return pixels;
}

#pragma mark - Bitmap image rep

@interface FOSBitmapImageRep ()

- (instancetype)initWithPixels:(NSMutableData *)pixels
                         width:(size_t)width
                        height:(size_t)height
                    colorSpace:(FOSColorSpace *)colorSpace NS_DESIGNATED_INITIALIZER;

@end

@implementation FOSBitmapImageRep {
    NSMutableData *_pixels;
    size_t _width;
    size_t _height;
    FOSColorSpace *_colorSpace;
}

+ (nullable FOSBitmapImageRep *)imageRepWithData:(NSData *)data {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (source == NULL) {
        return nil;
    }
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (image == NULL) {
        return nil;
    }
    FOSColorSpace *colorSpace = nil;
    NSMutableData *pixels = nil;
    if (FOSIsStraightRGBA8(image)) {
        // The usual case for the game's PNGs: keep the exact values, alpha included, as AppKit does.
        pixels = FOSCopyStraightRGBA8(image);
        colorSpace = FOSColorSpaceFor(CGImageGetColorSpace(image));
    }
    if (pixels == nil) {
        // Grayscale, palette, 16-bit and the like: convert, as AppKit would for an sRGB request.
        colorSpace = [FOSColorSpace sRGBColorSpace];
        pixels = FOSRenderRGBA8(image, colorSpace.CGColorSpace, kCGRenderingIntentDefault);
    }
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    CGImageRelease(image);
    if (pixels == nil || colorSpace == nil) {
        return nil;
    }
    return [[FOSBitmapImageRep alloc] initWithPixels:pixels width:width height:height colorSpace:colorSpace];
}

- (instancetype)initWithPixels:(NSMutableData *)pixels
                         width:(size_t)width
                        height:(size_t)height
                    colorSpace:(FOSColorSpace *)colorSpace {
    self = [super init];
    if (self != nil) {
        _pixels = pixels;
        _width = width;
        _height = height;
        _colorSpace = colorSpace;
    }
    return self;
}

- (unsigned char *)bitmapData {
    return _pixels.mutableBytes;
}

- (NSInteger)bitsPerPixel {
    return 32;
}

- (NSInteger)samplesPerPixel {
    return 4;
}

- (NSInteger)pixelsHigh {
    return (NSInteger)_height;
}

- (NSInteger)pixelsWide {
    return (NSInteger)_width;
}

- (FOSColorSpace *)colorSpace {
    return _colorSpace;
}

- (nullable FOSBitmapImageRep *)bitmapImageRepByConvertingToColorSpace:(FOSColorSpace *)space
                                                       renderingIntent:(NSInteger)intent {
    if (space == _colorSpace) {
        return self;
    }
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)_pixels);
    if (provider == NULL) {
        return nil;
    }
    CGImageRef image = CGImageCreate(_width, _height, 8, 32, _width * 4, _colorSpace.CGColorSpace,
                                     (CGBitmapInfo)kCGImageAlphaLast, provider, NULL, false,
                                     kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    if (image == NULL) {
        return nil;
    }
    // NSColorRenderingIntent and CGColorRenderingIntent number the same intents the same way.
    CGColorRenderingIntent cgIntent = intent >= 0 && intent <= kCGRenderingIntentSaturation
                                          ? (CGColorRenderingIntent)intent
                                          : kCGRenderingIntentDefault;
    NSMutableData *pixels = FOSRenderRGBA8(image, space.CGColorSpace, cgIntent);
    CGImageRelease(image);
    if (pixels == nil) {
        return nil;
    }
    return [[FOSBitmapImageRep alloc] initWithPixels:pixels width:_width height:_height colorSpace:space];
}

- (nullable FOSBitmapImageRep *)bitmapImageRepByRetaggingWithColorSpace:(FOSColorSpace *)space {
    if (space == _colorSpace) {
        return self;
    }
    NSMutableData *pixels = [_pixels mutableCopy];
    return [[FOSBitmapImageRep alloc] initWithPixels:pixels width:_width height:_height colorSpace:space];
}

@end
