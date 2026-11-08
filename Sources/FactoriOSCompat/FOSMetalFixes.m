#import "FOSTextureCompression.h"
#import "FactoriOSCompat.h"

@import Darwin;
@import Metal;
@import ObjectiveC;
@import QuartzCore;

// The game's Metal code (metal-cpp) was written for macOS. On iOS some of the selectors it sends don't exist and
// managed storage isn't allowed, so the fixes below are installed on the concrete Metal classes found at run time.
// Concrete class names are private and differ between GPUs, so they are taken from live objects rather than named.
//
// Unverifiable without a device: that the probed classes are the ones the game's objects have (they are when Metal
// API validation is off and on alike, since both wrap every object the same way), and that the game renders with
// these fixes; docs/feasibility.md lists this as a device gate.

// The Objective-C runtime hands out IMPs as `void (*)(void)`; calling one, or installing a function as one, means
// casting between that and the method's real signature. That is the runtime's documented calling convention.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-strict"

/// MTLStorageModeManaged and its resource-option form, which iOS's headers mark unavailable.
static const NSUInteger FOSStorageModeManaged = 1;

#pragma mark - Frame gate and frame-rate cap

static NSInteger fosFrameRateCap = 0;
static BOOL fosBackgrounded = NO;
static uint64_t fosPresentedFrameCount = 0;

static NSCondition *FOSFrameGate(void) {
    static NSCondition *gate;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gate = [[NSCondition alloc] init];
    });
    return gate;
}

static BOOL FOSIsBackgrounded(void) {
    NSCondition *gate = FOSFrameGate();
    [gate lock];
    BOOL backgrounded = fosBackgrounded;
    [gate unlock];
    return backgrounded;
}

void FOSCompatSetBackgrounded(BOOL backgrounded) {
    NSCondition *gate = FOSFrameGate();
    [gate lock];
    fosBackgrounded = backgrounded;
    [gate broadcast];
    [gate unlock];
}

void FOSCompatSetFrameRateCap(NSInteger framesPerSecond) {
    __atomic_store_n(&fosFrameRateCap, framesPerSecond, __ATOMIC_RELAXED);
}

uint64_t FOSCompatPresentedFrameCount(void) {
    return __atomic_load_n(&fosPresentedFrameCount, __ATOMIC_RELAXED);
}

/// Holds the calling thread while the app is in the background, where iOS ends apps that submit GPU work.
static void FOSWaitForForeground(void) {
    if (NSThread.isMainThread) {
        // The main thread has to keep its run loop turning, or the notification that the app is back never arrives.
        while (FOSIsBackgrounded()) {
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        return;
    }
    NSCondition *gate = FOSFrameGate();
    [gate lock];
    while (fosBackgrounded) {
        [gate wait];
    }
    [gate unlock];
}

#pragma mark - Runtime helpers

/// Points `selector` of `cls` at `replacement` and returns the implementation it had (its own or inherited); NULL,
/// with nothing changed, when instances of `cls` don't respond to `selector`.
static IMP _Nullable FOSSwizzle(Class cls, SEL selector, IMP replacement) {
    Method method = class_getInstanceMethod(cls, selector);
    if (method == NULL) {
        return NULL;
    }
    IMP original = method_getImplementation(method);
    if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method))) {
        // `cls` defines the method itself: replace it there (adding only works for inherited methods).
        original = method_setImplementation(method, replacement);
    }
    return original;
}

/// Adds a method the macOS API has and iOS lacks, unless the class already responds to it.
static void FOSAddMethod(Class cls, const char *name, IMP implementation, const char *types) {
    SEL selector = sel_registerName(name);
    if (!class_respondsToSelector(cls, selector)) {
        class_addMethod(cls, selector, implementation, types);
    }
}

/// Resource options with managed storage turned into shared storage; Apple GPUs share memory with the CPU.
static MTLResourceOptions FOSSharedOptions(MTLResourceOptions options) {
    MTLResourceOptions mask = (MTLResourceOptions)MTLResourceStorageModeMask;
    if (((options & mask) >> MTLResourceStorageModeShift) == FOSStorageModeManaged) {
        return (MTLResourceOptions)((options & ~mask) | MTLResourceStorageModeShared);
    }
    return options;
}

#pragma mark - Added methods

/// -[MTLBuffer didModifyRange:]: tells a managed buffer's GPU copy about CPU writes. Shared storage has one copy that
/// CPU and GPU both see (Apple GPUs use unified memory), so there is nothing to do.
static void FOSBufferDidModifyRange(id buffer, SEL cmd, NSRange range) {
    (void)buffer, (void)cmd, (void)range;
}

/// -[MTLBlitCommandEncoder synchronizeResource:]: copies a managed resource back to the CPU. Unified memory: nothing.
static void FOSBlitSynchronizeResource(id encoder, SEL cmd, id resource) {
    (void)encoder, (void)cmd, (void)resource;
}

/// -[MTLBlitCommandEncoder synchronizeTexture:slice:level:]: the same for one texture image. Unified memory: nothing.
static void FOSBlitSynchronizeTexture(id encoder, SEL cmd, id texture, NSUInteger slice, NSUInteger level) {
    (void)encoder, (void)cmd, (void)texture, (void)slice, (void)level;
}

/// -[MTLDevice isLowPower]: whether this is a Mac's integrated GPU next to a discrete one. An iOS device has a single
/// GPU, never the "low power" one of a pair.
static BOOL FOSDeviceIsLowPower(id device, SEL cmd) {
    (void)device, (void)cmd;
    return NO;
}

/// -[MTLDevice isDepth24Stencil8PixelFormatSupported]: whether MTLPixelFormatDepth24Unorm_Stencil8 exists, which only
/// some Intel and AMD Macs had. Apple GPUs never support it, so the game picks Depth32Float_Stencil8.
static BOOL FOSDeviceIsDepth24Stencil8PixelFormatSupported(id device, SEL cmd) {
    (void)device, (void)cmd;
    return NO;
}

static char FOSDisplaySyncKey;

/// -[CAMetalLayer setDisplaySyncEnabled:]: iOS always presents in sync with the display, so the value is only kept
/// for the getter.
static void FOSLayerSetDisplaySyncEnabled(id layer, SEL cmd, BOOL enabled) {
    (void)cmd;
    objc_setAssociatedObject(layer, &FOSDisplaySyncKey, [NSNumber numberWithBool:enabled],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

/// -[CAMetalLayer displaySyncEnabled]: the last value set; YES (what iOS does) by default.
static BOOL FOSLayerDisplaySyncEnabled(id layer, SEL cmd) {
    (void)cmd;
    NSNumber *enabled = objc_getAssociatedObject(layer, &FOSDisplaySyncKey);
    if (enabled == nil) {
        return YES;
    }
    return enabled.boolValue;
}

#pragma mark - Storage-mode swizzles

// Creation methods return +1 objects (the "new" family); the replacements pass the pointer through as `void *`, so
// ARC neither retains nor releases it and the caller gets the original's ownership.

typedef void *(*FOSNewBufferIMP)(id, SEL, NSUInteger, MTLResourceOptions);
typedef void *(*FOSNewBufferBytesIMP)(id, SEL, const void *, NSUInteger, MTLResourceOptions);
typedef void *(*FOSNewBufferNoCopyIMP)(id, SEL, void *, NSUInteger, MTLResourceOptions, id);
typedef void *(*FOSNewTextureIMP)(id, SEL, MTLTextureDescriptor *);
typedef void (*FOSSetStorageModeIMP)(id, SEL, MTLStorageMode);
typedef void (*FOSSetResourceOptionsIMP)(id, SEL, MTLResourceOptions);

static FOSNewBufferIMP fosNewBuffer;
static FOSNewBufferBytesIMP fosNewBufferBytes;
static FOSNewBufferNoCopyIMP fosNewBufferNoCopy;
static FOSNewTextureIMP fosNewTexture;
static FOSSetStorageModeIMP fosSetStorageMode;
static FOSSetResourceOptionsIMP fosSetResourceOptions;

static void *FOSNewBuffer(id device, SEL cmd, NSUInteger length, MTLResourceOptions options) {
    return fosNewBuffer(device, cmd, length, FOSSharedOptions(options));
}

static void *FOSNewBufferBytes(id device, SEL cmd, const void *bytes, NSUInteger length, MTLResourceOptions options) {
    return fosNewBufferBytes(device, cmd, bytes, length, FOSSharedOptions(options));
}

static void *FOSNewBufferNoCopy(id device, SEL cmd, void *bytes, NSUInteger length, MTLResourceOptions options,
                                id deallocator) {
    return fosNewBufferNoCopy(device, cmd, bytes, length, FOSSharedOptions(options), deallocator);
}

static void FOSSetStorageMode(id descriptor, SEL cmd, MTLStorageMode mode) {
    BOOL managed = (NSUInteger)mode == FOSStorageModeManaged;
    fosSetStorageMode(descriptor, cmd, managed ? MTLStorageModeShared : mode);
}

static void FOSSetResourceOptions(id descriptor, SEL cmd, MTLResourceOptions options) {
    fosSetResourceOptions(descriptor, cmd, FOSSharedOptions(options));
}

#pragma mark - BC texture emulation

// Apple's iPhone GPUs have no BC formats (supportsBCTextureCompression is NO), yet the game creates BC textures
// unconditionally, as every Mac it runs on samples them. On such a GPU a BC texture is created in the uncompressed
// format with the same channels, tagged with its BC format, and every upload into it is decoded on the CPU.
// The game uploads texels only through -copyFromBuffer:...toTexture:...destinationOrigin: from a shared staging buffer
// it filled beforehand; FactorioConfig turns off texture compression on these GPUs, so no BC data comes from the GPU.

static BOOL fosEmulateBC = NO;
static char FOSCompressedFormatKey;

typedef void (*FOSCopyBufferToTextureIMP)(id, SEL, id, NSUInteger, NSUInteger, NSUInteger, MTLSize, id, NSUInteger,
                                          NSUInteger, MTLOrigin);
static FOSCopyBufferToTextureIMP fosCopyBufferToTexture;

/// -[MTLDevice newTextureWithDescriptor:]: managed storage becomes shared, and a BC format becomes its decoded format
/// when the GPU lacks BC.
static void *FOSNewTexture(id device, SEL cmd, MTLTextureDescriptor *descriptor) {
    MTLPixelFormat format = descriptor.pixelFormat;
    MTLPixelFormat decoded = fosEmulateBC ? FOSBCDecodedFormat(format) : MTLPixelFormatInvalid;
    BOOL managed = (NSUInteger)descriptor.storageMode == FOSStorageModeManaged;
    if (!managed && decoded == MTLPixelFormatInvalid) {
        return fosNewTexture(device, cmd, descriptor);
    }
    MTLTextureDescriptor *adapted = [descriptor copy];
    if (managed) {
        adapted.storageMode = MTLStorageModeShared;
    }
    if (decoded == MTLPixelFormatInvalid) {
        return fosNewTexture(device, cmd, adapted);
    }
    adapted.pixelFormat = decoded;
    void *texture = fosNewTexture(device, cmd, adapted);
    if (texture != NULL) {
        objc_setAssociatedObject((__bridge id)texture, &FOSCompressedFormatKey,
                                 [NSNumber numberWithUnsignedInteger:format], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return texture;
}

/// Decodes `size` texels of BC `format` from `buffer` into a new shared buffer of the decoded format, rows packed;
/// nil, logged, when the source isn't CPU-visible or lies outside the buffer.
static id<MTLBuffer> _Nullable FOSDecodeUpload(id<MTLDevice> device, id<MTLBuffer> buffer, NSUInteger offset,
                                               NSUInteger bytesPerRow, NSUInteger bytesPerImage, MTLSize size,
                                               MTLPixelFormat format) {
    NSUInteger blockRows = (size.height + 3) / 4;
    NSUInteger sourceImage = size.depth > 1 ? bytesPerImage : blockRows * bytesPerRow;
    const uint8_t *source = (const uint8_t *)buffer.contents;
    if (source == NULL || size.depth == 0 ||
        offset + ((size.depth - 1) * sourceImage) + (blockRows * bytesPerRow) > buffer.length) {
        NSLog(@"FactoriOS: can't decode a BC upload of %lux%lu (CPU-visible: %d)", (unsigned long)size.width,
              (unsigned long)size.height, source != NULL);
        return nil;
    }
    NSUInteger rowBytes = size.width * FOSBCDecodedBytesPerPixel(format);
    NSUInteger imageBytes = rowBytes * size.height;
    id<MTLBuffer> decoded = [device newBufferWithLength:imageBytes * size.depth options:MTLResourceStorageModeShared];
    uint8_t *destination = (uint8_t *)decoded.contents;
    for (NSUInteger image = 0; image < size.depth; image++) {
        FOSBCDecode(format, source + offset + (image * sourceImage), bytesPerRow, size.width, size.height,
                    destination + (image * imageBytes), rowBytes);
    }
    return decoded;
}

/// -[MTLBlitCommandEncoder copyFromBuffer:...toTexture:...destinationOrigin:]: an upload into an emulated BC texture
/// copies the decoded texels instead. The command buffer retains the decoded buffer until the copy has run.
static void FOSCopyBufferToTexture(id encoder, SEL cmd, id buffer, NSUInteger offset, NSUInteger bytesPerRow,
                                   NSUInteger bytesPerImage, MTLSize size, id texture, NSUInteger slice,
                                   NSUInteger level, MTLOrigin origin) {
    NSNumber *compressed = objc_getAssociatedObject(texture, &FOSCompressedFormatKey);
    if (compressed == nil) {
        fosCopyBufferToTexture(encoder, cmd, buffer, offset, bytesPerRow, bytesPerImage, size, texture, slice, level,
                               origin);
        return;
    }
    MTLPixelFormat format = (MTLPixelFormat)compressed.unsignedIntegerValue;
    id<MTLBuffer> decoded = FOSDecodeUpload(((id<MTLCommandEncoder>)encoder).device, buffer, offset, bytesPerRow,
                                            bytesPerImage, size, format);
    if (decoded == nil) {
        return;
    }
    NSUInteger rowBytes = size.width * FOSBCDecodedBytesPerPixel(format);
    fosCopyBufferToTexture(encoder, cmd, decoded, 0, rowBytes, rowBytes * size.height, size, texture, slice, level,
                           origin);
}

#pragma mark - Presentation swizzles

typedef void (*FOSPresentDrawableIMP)(id, SEL, id);
typedef void *(*FOSNextDrawableIMP)(id, SEL);

static FOSPresentDrawableIMP fosPresentDrawable;
static FOSNextDrawableIMP fosNextDrawable;

/// Set while the cap's own presentation runs, in case Metal implements it through presentDrawable:.
static _Thread_local BOOL fosPresentingCapped = NO;

/// -[MTLCommandBuffer presentDrawable:] with the frame-rate cap: each frame stays on screen at least 1/cap seconds.
static void FOSPresentDrawable(id commandBuffer, SEL cmd, id drawable) {
    if (!fosPresentingCapped) {
        __atomic_add_fetch(&fosPresentedFrameCount, 1, __ATOMIC_RELAXED);
    }
    NSInteger cap = __atomic_load_n(&fosFrameRateCap, __ATOMIC_RELAXED);
    if (cap <= 0 || fosPresentingCapped) {
        fosPresentDrawable(commandBuffer, cmd, drawable);
        return;
    }
    fosPresentingCapped = YES;
#if TARGET_OS_SIMULATOR
    // The simulator's MTLCommandBuffer protocol omits afterMinimumDuration; launcher testing doesn't need a GPU cap.
    fosPresentDrawable(commandBuffer, cmd, drawable);
#else
    [(id<MTLCommandBuffer>)commandBuffer presentDrawable:drawable afterMinimumDuration:1.0 / (CFTimeInterval)cap];
#endif
    fosPresentingCapped = NO;
}

/// -[CAMetalLayer nextDrawable], held while the app is in the background. The drawable is returned autoreleased,
/// untouched (`void *`), as the original returns it.
static void *FOSNextDrawable(id layer, SEL cmd) {
    FOSWaitForForeground();
    return fosNextDrawable(layer, cmd);
}

#pragma mark - Installation

/// Live objects of the classes the fixes go on, and the GPU's BC support. Classes live for the process, so the fields
/// needn't retain them.
typedef struct {
    __unsafe_unretained Class device;
    __unsafe_unretained Class buffer;
    __unsafe_unretained Class commandBuffer;
    __unsafe_unretained Class blitEncoder;
    __unsafe_unretained Class textureDescriptor;
    BOOL supportsBC;
} FOSMetalClasses;

static BOOL FOSProbeMetalClasses(FOSMetalClasses *classes) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    id<MTLBuffer> buffer = [device newBufferWithLength:16 options:MTLResourceStorageModeShared];
    id<MTLCommandQueue> queue = [device newCommandQueue];
    id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];
    id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
    [blitEncoder endEncoding];
    MTLTextureDescriptor *descriptor = [[MTLTextureDescriptor alloc] init];
    if (device == nil || buffer == nil || commandBuffer == nil || blitEncoder == nil) {
        return NO;
    }
    classes->device = object_getClass(device);
    classes->buffer = object_getClass(buffer);
    classes->commandBuffer = object_getClass(commandBuffer);
    classes->blitEncoder = object_getClass(blitEncoder);
    classes->textureDescriptor = object_getClass(descriptor);
    classes->supportsBC = device.supportsBCTextureCompression;
    return YES;
}

static void FOSInstallStorageFixes(const FOSMetalClasses *classes) {
    fosNewBuffer = (FOSNewBufferIMP)FOSSwizzle(classes->device, sel_registerName("newBufferWithLength:options:"),
                                               (IMP)FOSNewBuffer);
    fosNewBufferBytes = (FOSNewBufferBytesIMP)FOSSwizzle(
        classes->device, sel_registerName("newBufferWithBytes:length:options:"), (IMP)FOSNewBufferBytes);
    fosNewBufferNoCopy = (FOSNewBufferNoCopyIMP)FOSSwizzle(
        classes->device, sel_registerName("newBufferWithBytesNoCopy:length:options:deallocator:"),
        (IMP)FOSNewBufferNoCopy);
    fosNewTexture = (FOSNewTextureIMP)FOSSwizzle(classes->device, sel_registerName("newTextureWithDescriptor:"),
                                                 (IMP)FOSNewTexture);
    fosSetStorageMode = (FOSSetStorageModeIMP)FOSSwizzle(classes->textureDescriptor,
                                                         sel_registerName("setStorageMode:"), (IMP)FOSSetStorageMode);
    fosSetResourceOptions = (FOSSetResourceOptionsIMP)FOSSwizzle(
        classes->textureDescriptor, sel_registerName("setResourceOptions:"), (IMP)FOSSetResourceOptions);
}

/// Turns on BC emulation when the GPU lacks BC; FOSNewTexture checks the flag, the upload hook goes on the encoder.
static void FOSInstallBCEmulation(const FOSMetalClasses *classes) {
    if (classes->supportsBC) {
        return;
    }
    fosCopyBufferToTexture = (FOSCopyBufferToTextureIMP)FOSSwizzle(
        classes->blitEncoder,
        sel_registerName("copyFromBuffer:sourceOffset:sourceBytesPerRow:sourceBytesPerImage:sourceSize:toTexture:"
                         "destinationSlice:destinationLevel:destinationOrigin:"),
        (IMP)FOSCopyBufferToTexture);
    fosEmulateBC = fosCopyBufferToTexture != NULL;
}

static void FOSInstallMissingMethods(const FOSMetalClasses *classes) {
    FOSAddMethod(classes->buffer, "didModifyRange:", (IMP)FOSBufferDidModifyRange, "v@:{_NSRange=QQ}");
    FOSAddMethod(classes->blitEncoder, "synchronizeResource:", (IMP)FOSBlitSynchronizeResource, "v@:@");
    FOSAddMethod(classes->blitEncoder, "synchronizeTexture:slice:level:", (IMP)FOSBlitSynchronizeTexture, "v@:@QQ");
    FOSAddMethod(classes->device, "isLowPower", (IMP)FOSDeviceIsLowPower, "B@:");
    FOSAddMethod(
        classes->device, "isDepth24Stencil8PixelFormatSupported", (IMP)FOSDeviceIsDepth24Stencil8PixelFormatSupported,
        "B@:"
    );
    Class layer = [CAMetalLayer class];
    FOSAddMethod(layer, "setDisplaySyncEnabled:", (IMP)FOSLayerSetDisplaySyncEnabled, "v@:B");
    FOSAddMethod(layer, "displaySyncEnabled", (IMP)FOSLayerDisplaySyncEnabled, "B@:");
}

static void FOSInstallPresentationFixes(const FOSMetalClasses *classes) {
    fosPresentDrawable = (FOSPresentDrawableIMP)FOSSwizzle(classes->commandBuffer, sel_registerName("presentDrawable:"),
                                                           (IMP)FOSPresentDrawable);
    fosNextDrawable = (FOSNextDrawableIMP)FOSSwizzle([CAMetalLayer class], sel_registerName("nextDrawable"),
                                                     (IMP)FOSNextDrawable);
}

void FOSCompatInstallMetalFixes(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        FOSMetalClasses classes = {Nil, Nil, Nil, Nil, Nil, YES};
        if (!FOSProbeMetalClasses(&classes)) {
            // No Metal device: the game can't render at all and reports that itself.
            NSLog(@"FactoriOS: no Metal device; Metal fixes not installed");
            return;
        }
        FOSInstallStorageFixes(&classes);
        FOSInstallBCEmulation(&classes);
        FOSInstallMissingMethods(&classes);
        FOSInstallPresentationFixes(&classes);
    });
}

#pragma clang diagnostic pop
