#import "FactoriOSCompat.h"
#import "FOSAppKit.h"

@import Darwin;
@import Metal;
@import Security;

#pragma mark - State set by the runtime

/// Guards the executable path and the restart handler, which the game may read from any thread.
static pthread_mutex_t fosStateLock = PTHREAD_MUTEX_INITIALIZER;
static char *_Nullable fosExecutablePath = NULL;
static void (^_Nullable fosRestartHandler)(NSArray<NSString *> *arguments) = nil;

void FOSCompatSetExecutablePath(const char *path) {
    char *copy = strdup(path);
    pthread_mutex_lock(&fosStateLock);
    char *old = fosExecutablePath;
    fosExecutablePath = copy;
    pthread_mutex_unlock(&fosStateLock);
    free(old);
}

void FOSCompatSetRestartHandler(void (^handler)(NSArray<NSString *> *arguments)) {
    pthread_mutex_lock(&fosStateLock);
    fosRestartHandler = handler;
    pthread_mutex_unlock(&fosStateLock);
}

#pragma mark - AppKit: NSApp

/// What the game's `NSApp` reads: there is no NSApplication on iOS, so it stays nil and the menu-bar code the game
/// runs on start-up (setup_macos_application_menu_bar) messages nil, which does nothing.
static __unsafe_unretained id fosNSApp = nil;

#pragma mark - Foundation: NSAppleEventManager

@implementation FOSAppleEventManager
@end

#pragma mark - ApplicationServices

/// UAZoomEnabled. iOS has no public way to ask whether Zoom is on, so this answers false, and the game keeps its
/// cursor handling as on a Mac without Zoom.
static Boolean fos_UAZoomEnabled(void) {
    return false;
}

#pragma mark - IOKit power assertions

typedef uint32_t FOSIOPMAssertionID;
typedef int32_t FOSIOReturn;
static const FOSIOReturn FOSIOReturnNotFound = (int32_t)0xE00002F0U;  // kIOReturnNotFound

/// IOPMAssertionRelease. The game's own code releases an assertion (SystemUtil::preventSleep) but never creates one;
/// only its static SDL's Cocoa backend does, which never runs, so there is never one to release.
static FOSIOReturn fos_IOPMAssertionRelease(FOSIOPMAssertionID assertionID) {
    (void)assertionID;
    return FOSIOReturnNotFound;
}

#pragma mark - OpenCL

// iOS has no OpenCL. The game only uses it to list GPUs (GPUDetectionOpenGL::createGPUListUsingOpenCL); with no
// platform it falls back to what Metal reports. The answers are the ones an OpenCL ICD loader gives with no driver.

typedef int32_t FOSCLInt;
typedef uint32_t FOSCLUInt;
typedef uint64_t FOSCLDeviceType;
typedef struct FOSCLPlatform *FOSCLPlatformID;
typedef struct FOSCLDevice *FOSCLDeviceID;

static const FOSCLInt FOSCLInvalidValue = -30;          // CL_INVALID_VALUE
static const FOSCLInt FOSCLInvalidPlatform = -32;       // CL_INVALID_PLATFORM
static const FOSCLInt FOSCLInvalidDevice = -33;         // CL_INVALID_DEVICE
static const FOSCLInt FOSCLPlatformNotFound = -1001;    // CL_PLATFORM_NOT_FOUND_KHR

static FOSCLInt fos_clGetPlatformIDs(FOSCLUInt numEntries, FOSCLPlatformID *platforms, FOSCLUInt *numPlatforms) {
    if ((numEntries == 0 && platforms != NULL) || (platforms == NULL && numPlatforms == NULL)) {
        return FOSCLInvalidValue;
    }
    if (numPlatforms != NULL) {
        *numPlatforms = 0;
    }
    return FOSCLPlatformNotFound;
}

static FOSCLInt fos_clGetDeviceIDs(FOSCLPlatformID platform, FOSCLDeviceType deviceType, FOSCLUInt numEntries,
                                   FOSCLDeviceID *devices, FOSCLUInt *numDevices) {
    // No platform exists, so whatever the game passes isn't one.
    (void)platform, (void)deviceType, (void)numEntries, (void)devices;
    if (numDevices != NULL) {
        *numDevices = 0;
    }
    return FOSCLInvalidPlatform;
}

static FOSCLInt fos_clGetDeviceInfo(FOSCLDeviceID device, FOSCLUInt paramName, size_t paramValueSize,
                                    void *paramValue, size_t *paramValueSizeReturn) {
    // No device exists, so whatever the game passes isn't one.
    (void)device, (void)paramName, (void)paramValueSize, (void)paramValue;
    if (paramValueSizeReturn != NULL) {
        *paramValueSizeReturn = 0;
    }
    return FOSCLInvalidDevice;
}

#pragma mark - Metal device discovery

/// MTLDeviceNotificationHandler (macOS only): called on GPU hot-plug, which iOS doesn't have.
typedef void (^FOSDeviceNotificationHandler)(id<MTLDevice> device, NSString *notification);

/// MTLCopyAllDevices: the one GPU iOS has. Returns +1, as its name promises.
static NSArray<id<MTLDevice>> *fos_MTLCopyAllDevices(void) NS_RETURNS_RETAINED;
static NSArray<id<MTLDevice>> *fos_MTLCopyAllDevices(void) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    return device != nil ? @[device] : @[];
}

/// The observer token MTLCopyAllDevicesWithObserver hands out; it lives for the process, so the caller may keep it.
static NSObject *FOSDeviceObserverToken(void) {
    static NSObject *token;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        token = [[NSObject alloc] init];
    });
    return token;
}

static NSArray<id<MTLDevice>> *fos_MTLCopyAllDevicesWithObserver(__autoreleasing id<NSObject> *observer,
                                                                 FOSDeviceNotificationHandler handler)
    NS_RETURNS_RETAINED;
static NSArray<id<MTLDevice>> *fos_MTLCopyAllDevicesWithObserver(__autoreleasing id<NSObject> *observer,
                                                                 FOSDeviceNotificationHandler handler) {
    // iOS GPUs are never added or removed, so the handler is never called.
    (void)handler;
    if (observer != NULL) {
        *observer = FOSDeviceObserverToken();
    }
    return fos_MTLCopyAllDevices();
}

static void fos_MTLRemoveDeviceObserver(id<NSObject> observer) {
    // fos_MTLCopyAllDevicesWithObserver registers nothing, so there is nothing to remove.
    (void)observer;
}

#pragma mark - Security

/// SecCertificateCopyLongDescription (macOS only): the game's libcurl calls it, unchecked, for a server certificate's
/// subject while it verifies a TLS connection. iOS's equivalent is the certificate's subject summary.
static CFStringRef _Nullable fos_SecCertificateCopyLongDescription(CFAllocatorRef _Nullable allocator,
                                                                   SecCertificateRef certificate,
                                                                   CFErrorRef _Nullable *_Nullable error) {
    CFStringRef summary = SecCertificateCopySubjectSummary(certificate);
    if (summary == NULL && error != NULL) {
        *error = CFErrorCreate(allocator, kCFErrorDomainOSStatus, errSecDecode, NULL);
    }
    return summary;
}

#pragma mark - Process control

/// execv: iOS can't replace its process. The game calls this to restart itself (after mod changes, for example), so
/// the runtime's restart handler gets the arguments on the main thread and tells the player to reopen FactoriOS.
static int fos_execv(const char *path, char *const argv[]) {
    (void)path;
    NSMutableArray<NSString *> *arguments = [NSMutableArray array];
    for (size_t index = 0; argv != NULL && argv[index] != NULL; index++) {
        NSString *argument = [NSString stringWithUTF8String:argv[index]];
        if (argument != nil) {
            [arguments addObject:argument];
        }
    }
    // The runtime sets the handler before it loads the game, so it is there whenever the game can call execv.
    pthread_mutex_lock(&fosStateLock);
    void (^handler)(NSArray<NSString *> *) = fosRestartHandler;
    pthread_mutex_unlock(&fosStateLock);
    NSArray<NSString *> *requested = [arguments copy];
    if (NSThread.isMainThread) {
        handler(requested);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(requested);
        });
    }
    // Reached when the handler went to the main queue or returned: report the failure exec would, which the game logs.
    errno = EPERM;
    return -1;
}

/// fork: iOS apps can't create processes. The game treats the failure as a child process that couldn't start.
static pid_t fos_fork(void) {
    errno = ENOSYS;
    return -1;
}

/// _NSGetExecutablePath: the imported game's macOS executable, so the game finds its own files next to it.
static int fos_NSGetExecutablePath(char *buffer, uint32_t *bufferSize) {
    // The runtime sets the path before it loads the game, so it is there whenever the game can ask.
    pthread_mutex_lock(&fosStateLock);
    char *path = strdup(fosExecutablePath);
    pthread_mutex_unlock(&fosStateLock);
    size_t needed = strlen(path) + 1;
    int result = 0;
    if (needed > *bufferSize) {
        *bufferSize = (uint32_t)needed;
        result = -1;
    } else {
        memcpy(buffer, path, needed);
    }
    free(path);
    return result;
}

#pragma mark - The table

const FOSSymbolReplacement *FOSCompatReplacements(size_t *count) {
    static FOSSymbolReplacement table[17];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        FOSSymbolReplacement entries[17] = {
            {"_NSApp", (const void *)&fosNSApp},
            {"_OBJC_CLASS_$_NSAppleEventManager", (__bridge const void *)[FOSAppleEventManager class]},
            {"_OBJC_CLASS_$_NSBitmapImageRep", (__bridge const void *)[FOSBitmapImageRep class]},
            {"_OBJC_CLASS_$_NSColorSpace", (__bridge const void *)[FOSColorSpace class]},
            {"_OBJC_CLASS_$_NSWorkspace", (__bridge const void *)[FOSWorkspace class]},
            {"_UAZoomEnabled", (const void *)fos_UAZoomEnabled},
            {"_IOPMAssertionRelease", (const void *)fos_IOPMAssertionRelease},
            {"_clGetPlatformIDs", (const void *)fos_clGetPlatformIDs},
            {"_clGetDeviceIDs", (const void *)fos_clGetDeviceIDs},
            {"_clGetDeviceInfo", (const void *)fos_clGetDeviceInfo},
            {"_MTLCopyAllDevices", (const void *)fos_MTLCopyAllDevices},
            {"_MTLCopyAllDevicesWithObserver", (const void *)fos_MTLCopyAllDevicesWithObserver},
            {"_MTLRemoveDeviceObserver", (const void *)fos_MTLRemoveDeviceObserver},
            {"_SecCertificateCopyLongDescription", (const void *)fos_SecCertificateCopyLongDescription},
            {"_execv", (const void *)fos_execv},
            {"_fork", (const void *)fos_fork},
            {"__NSGetExecutablePath", (const void *)fos_NSGetExecutablePath},
        };
        memcpy(table, entries, sizeof(entries));
    });
    *count = sizeof(table) / sizeof(table[0]);
    return table;
}

#pragma mark - Slot patching

int FOSCompatWriteSlot(void *slot, const void *value) {
    vm_address_t region = (vm_address_t)slot;
    vm_size_t regionSize = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t objectName = MACH_PORT_NULL;
    kern_return_t result = vm_region_64(mach_task_self(), &region, &regionSize, VM_REGION_BASIC_INFO_64,
                                        (vm_region_info_t)&info, &infoCount, &objectName);
    if (result != KERN_SUCCESS) {
        return result;
    }
    // Slots are 8-byte aligned, so one never straddles two pages.
    vm_size_t pageSize = vm_page_size;
    vm_address_t page = (vm_address_t)slot & ~(pageSize - 1);
    result = vm_protect(mach_task_self(), page, pageSize, FALSE, VM_PROT_READ | VM_PROT_WRITE);
    if (result == KERN_PROTECTION_FAILURE) {
        // A read-only mapping of the file (__DATA_CONST after dyld's fixups): take a private copy of the page, which
        // data pages allow; code signing only covers executable pages.
        result = vm_protect(mach_task_self(), page, pageSize, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    }
    if (result != KERN_SUCCESS) {
        return result;
    }
    memcpy(slot, (const void *)&value, sizeof(value));
    return vm_protect(mach_task_self(), page, pageSize, FALSE, info.protection);
}
