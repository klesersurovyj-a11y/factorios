#import "FactoriOSCompat.h"

@import ObjectiveC;
@import UIKit;

// SDL's UIKit window (SDL_uikitwindow) resets its frame to the screen's bounds in layoutSubviews, an old orientation
// workaround. To keep the game off the camera housing and inside the Frame margin, a window given a fixed frame here
// lays out as a plain UIWindow instead, with its frame put back if something else moved it; windows without one keep
// SDL's behaviour.
//
// SDL's view controller then reports the inset size to the game (it sizes its view from the window's bounds in
// viewDidLayoutSubviews): on an iPhone 14 with the housing inset, Factorio logs a 797x390 window on the 844x390 screen.

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-strict"

typedef void (*FOSLayoutSubviewsIMP)(id, SEL);

static char FOSWindowFrameKey;
static __unsafe_unretained Class fosSwizzledWindowClass = Nil;
static FOSLayoutSubviewsIMP fosOriginalLayoutSubviews = NULL;
static FOSLayoutSubviewsIMP fosPlainLayoutSubviews = NULL;

static void FOSWindowLayoutSubviews(UIWindow *window, SEL cmd) {
    NSValue *fixed = objc_getAssociatedObject(window, &FOSWindowFrameKey);
    if (fixed == nil) {
        fosOriginalLayoutSubviews(window, cmd);
        return;
    }
    CGRect frame = fixed.CGRectValue;
    if (!CGRectEqualToRect(window.frame, frame)) {
        window.frame = frame;
    }
    fosPlainLayoutSubviews(window, cmd);
}

/// Routes layoutSubviews of `cls` through FOSWindowLayoutSubviews, once, when the class overrides UIWindow's.
static void FOSInstallLayoutOverride(Class cls) {
    if (fosSwizzledWindowClass != Nil) {
        return;
    }
    SEL selector = sel_registerName("layoutSubviews");
    Method method = class_getInstanceMethod(cls, selector);
    IMP plain = class_getMethodImplementation([UIWindow class], selector);
    if (method == NULL || method_getImplementation(method) == plain) {
        // The class lays out like a UIWindow already; setting the frame is enough.
        return;
    }
    fosPlainLayoutSubviews = (FOSLayoutSubviewsIMP)plain;
    IMP replacement = (IMP)FOSWindowLayoutSubviews;
    if (class_addMethod(cls, selector, replacement, method_getTypeEncoding(method))) {
        fosOriginalLayoutSubviews = (FOSLayoutSubviewsIMP)method_getImplementation(method);
    } else {
        fosOriginalLayoutSubviews = (FOSLayoutSubviewsIMP)method_setImplementation(method, replacement);
    }
    fosSwizzledWindowClass = cls;
}

void FOSCompatSetWindowFrame(UIWindow *window, CGRect frame) {
    Class cls = object_getClass(window);
    if (fosSwizzledWindowClass == Nil) {
        FOSInstallLayoutOverride(cls);
    }
    objc_setAssociatedObject(window, &FOSWindowFrameKey, [NSValue valueWithCGRect:frame],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    window.frame = frame;
    [window setNeedsLayout];
}

#pragma clang diagnostic pop
