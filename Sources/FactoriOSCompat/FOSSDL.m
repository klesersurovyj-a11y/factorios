#import "FOSSDL.h"

@import Darwin;
@import ObjectiveC;

NSErrorDomain const FOSSDLErrorDomain = @"FOSSDLErrorDomain";

// SDL3 3.2 ABI pieces the bridge uses (SDL_init.h, SDL_joystick.h, SDL_events.h, SDL_video.h, SDL_mouse.h).

typedef struct FOSSDLWindow FOSSDLWindow;
typedef struct FOSSDLJoystick FOSSDLJoystick;

static const uint32_t FOSSDLInitJoystick = 0x00000200U;  // SDL_INIT_JOYSTICK
static const uint32_t FOSSDLInitGamepad = 0x00002000U;   // SDL_INIT_GAMEPAD
static const uint16_t FOSSDLJoystickTypeGamepad = 1;     // SDL_JOYSTICK_TYPE_GAMEPAD
static const uint32_t FOSSDLEventMouseWheel = 0x403;     // SDL_EVENT_MOUSE_WHEEL
static const uint16_t FOSSDLGamepadButtons = 15;         // SDL_GAMEPAD_BUTTON_SOUTH ... SDL_GAMEPAD_BUTTON_DPAD_RIGHT
static const uint16_t FOSSDLGamepadAxes = 6;             // SDL_GAMEPAD_AXIS_LEFTX ... SDL_GAMEPAD_AXIS_RIGHT_TRIGGER

/// SDL_VirtualJoystickDesc. SDL checks `version` against its own sizeof (SDL_INIT_INTERFACE).
typedef struct {
    uint32_t version;
    uint16_t type;
    uint16_t padding;
    uint16_t vendor_id;
    uint16_t product_id;
    uint16_t naxes;
    uint16_t nbuttons;
    uint16_t nballs;
    uint16_t nhats;
    uint16_t ntouchpads;
    uint16_t nsensors;
    uint16_t padding2[2];
    uint32_t button_mask;
    uint32_t axis_mask;
    const char *name;
    const void *touchpads;
    const void *sensors;
    void *userdata;
    void (*Update)(void *userdata);
    void (*SetPlayerIndex)(void *userdata, int player_index);
    bool (*Rumble)(void *userdata, uint16_t low_frequency_rumble, uint16_t high_frequency_rumble);
    bool (*RumbleTriggers)(void *userdata, uint16_t left_rumble, uint16_t right_rumble);
    bool (*SetLED)(void *userdata, uint8_t red, uint8_t green, uint8_t blue);
    bool (*SendEffect)(void *userdata, const void *data, int size);
    bool (*SetSensorsEnabled)(void *userdata, bool enabled);
    void (*Cleanup)(void *userdata);
} FOSSDLVirtualJoystickDesc;

// SDL's own compile-time check (SDL_joystick.c) pins this size on 64-bit platforms.
_Static_assert(sizeof(FOSSDLVirtualJoystickDesc) == 136, "SDL_VirtualJoystickDesc layout");

/// SDL_MouseWheelEvent. `integer_x`/`integer_y` arrived in SDL 3.2.12; older builds see them as union padding.
typedef struct {
    uint32_t type;
    uint32_t reserved;
    uint64_t timestamp;
    uint32_t windowID;
    uint32_t which;
    float x;
    float y;
    uint32_t direction;
    float mouse_x;
    float mouse_y;
    int32_t integer_x;
    int32_t integer_y;
} FOSSDLMouseWheelEvent;

/// SDL_Event: a 128-byte union.
typedef union {
    uint32_t type;
    FOSSDLMouseWheelEvent wheel;
    uint8_t padding[128];
} FOSSDLEvent;

_Static_assert(sizeof(FOSSDLEvent) == 128, "SDL_Event size");

/// The SDL3 functions the bridge calls.
typedef struct {
    int (*RunApp)(int argc, char *_Nullable *_Nonnull argv, FOSSDLMainFunction mainFunction, void *_Nullable reserved);
    bool (*SetHint)(const char *name, const char *value);
    const char *(*GetError)(void);
    bool (*InitSubSystem)(uint32_t flags);
    uint32_t (*AttachVirtualJoystick)(const FOSSDLVirtualJoystickDesc *desc);
    bool (*DetachVirtualJoystick)(uint32_t instanceID);
    FOSSDLJoystick *_Nullable (*OpenJoystick)(uint32_t instanceID);
    void (*CloseJoystick)(FOSSDLJoystick *joystick);
    bool (*SetJoystickVirtualButton)(FOSSDLJoystick *joystick, int button, bool down);
    bool (*SetJoystickVirtualAxis)(FOSSDLJoystick *joystick, int axis, int16_t value);
    FOSSDLWindow *_Nullable *_Nullable (*GetWindows)(int *_Nullable count);
    uint32_t (*GetWindowID)(FOSSDLWindow *window);
    void (*WarpMouseInWindow)(FOSSDLWindow *_Nullable window, float x, float y);
    uint32_t (*GetMouseState)(float *_Nullable x, float *_Nullable y);
    bool (*PushEvent)(FOSSDLEvent *event);
    void (*Free)(void *_Nullable memory);
    uint32_t (*GetWindowProperties)(FOSSDLWindow *window);
    float (*GetWindowPixelDensity)(FOSSDLWindow *window);
    void *_Nullable (*GetPointerProperty)(uint32_t props, const char *name, void *_Nullable defaultValue);
} FOSSDLFunctions;

static FOSSDLFunctions fosSDL;
static BOOL fosSDLLoaded = NO;

/// The attached virtual gamepad: its instance ID, the open joystick and the rumble handler.
static uint32_t fosGamepadID = 0;
static FOSSDLJoystick *_Nullable fosGamepad = NULL;
static void (^_Nullable fosRumbleHandler)(float low, float high) = nil;

static NSError *FOSSDLMakeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:FOSSDLErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

/// Converts a C string without allowing invalid UTF-8 to escape as a nullable NSString.
static NSString *FOSStringFromUTF8(const char *bytes) {
    NSString *string = [NSString stringWithUTF8String:bytes];
    return string != nil ? string : @"";
}

/// Resolves one SDL function, noting its name when the library lacks it.
static void *_Nullable FOSSDLSymbol(void *handle, const char *name, NSMutableArray<NSString *> *missing) {
    void *symbol = dlsym(handle, name);
    if (symbol == NULL) {
        [missing addObject:FOSStringFromUTF8(name)];
    }
    return symbol;
}

static void FOSSDLResolve(void *handle, NSMutableArray<NSString *> *missing) {
    fosSDL.RunApp = (int (*)(int, char *_Nullable *_Nonnull, FOSSDLMainFunction, void *_Nullable))FOSSDLSymbol(
        handle, "SDL_RunApp", missing);
    fosSDL.SetHint = (bool (*)(const char *, const char *))FOSSDLSymbol(handle, "SDL_SetHint", missing);
    fosSDL.GetError = (const char *(*)(void))FOSSDLSymbol(handle, "SDL_GetError", missing);
    fosSDL.InitSubSystem = (bool (*)(uint32_t))FOSSDLSymbol(handle, "SDL_InitSubSystem", missing);
    fosSDL.AttachVirtualJoystick = (uint32_t (*)(const FOSSDLVirtualJoystickDesc *))FOSSDLSymbol(
        handle, "SDL_AttachVirtualJoystick", missing);
    fosSDL.DetachVirtualJoystick = (bool (*)(uint32_t))FOSSDLSymbol(handle, "SDL_DetachVirtualJoystick", missing);
    fosSDL.OpenJoystick = (FOSSDLJoystick * _Nullable (*)(uint32_t)) FOSSDLSymbol(handle, "SDL_OpenJoystick", missing);
    fosSDL.CloseJoystick = (void (*)(FOSSDLJoystick *))FOSSDLSymbol(handle, "SDL_CloseJoystick", missing);
    fosSDL.SetJoystickVirtualButton = (bool (*)(FOSSDLJoystick *, int, bool))FOSSDLSymbol(
        handle, "SDL_SetJoystickVirtualButton", missing);
    fosSDL.SetJoystickVirtualAxis = (bool (*)(FOSSDLJoystick *, int, int16_t))FOSSDLSymbol(
        handle, "SDL_SetJoystickVirtualAxis", missing);
    fosSDL.GetWindows = (FOSSDLWindow * _Nullable * _Nullable (*)(int *_Nullable))FOSSDLSymbol(
        handle, "SDL_GetWindows", missing);
    fosSDL.GetWindowID = (uint32_t (*)(FOSSDLWindow *))FOSSDLSymbol(handle, "SDL_GetWindowID", missing);
    fosSDL.WarpMouseInWindow = (void (*)(FOSSDLWindow *_Nullable, float, float))FOSSDLSymbol(
        handle, "SDL_WarpMouseInWindow", missing);
    fosSDL.GetMouseState = (uint32_t (*)(float *_Nullable, float *_Nullable))FOSSDLSymbol(
        handle, "SDL_GetMouseState", missing);
    fosSDL.PushEvent = (bool (*)(FOSSDLEvent *))FOSSDLSymbol(handle, "SDL_PushEvent", missing);
    fosSDL.Free = (void (*)(void *_Nullable))FOSSDLSymbol(handle, "SDL_free", missing);
    fosSDL.GetWindowProperties = (uint32_t (*)(FOSSDLWindow *))FOSSDLSymbol(
        handle, "SDL_GetWindowProperties", missing);
    fosSDL.GetPointerProperty = (void *_Nullable (*)(uint32_t, const char *, void *_Nullable))FOSSDLSymbol(
        handle, "SDL_GetPointerProperty", missing);
    fosSDL.GetWindowPixelDensity = (float (*)(FOSSDLWindow *))FOSSDLSymbol(
        handle, "SDL_GetWindowPixelDensity", missing);
}

static void FOSSDLWithFirstWindow(void (^body)(FOSSDLWindow *window));

/// SDL_Rect.
typedef struct {
    int x;
    int y;
    int w;
    int h;
} FOSSDLRect;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-strict"

typedef void (*FOSSetTextInputRectIMP)(id, SEL, FOSSDLRect);
static FOSSetTextInputRectIMP fosSetTextInputRect = NULL;

/// -[SDL_uikitviewcontroller setTextInputRect:]. SDL lifts its view above the keyboard so the game's focused text
/// field stays visible, measuring the field in the window's points; the game, rendering at native resolution, gives
/// it in its drawable's pixels, which would lift the view off the screen. The rect is turned into points first.
static void FOSSDLSetTextInputRect(id controller, SEL cmd, FOSSDLRect rect) {
    __block float density = 1;
    FOSSDLWithFirstWindow(^(FOSSDLWindow *window) {
        density = fosSDL.GetWindowPixelDensity(window);
    });
    if (density > 1) {
        rect.x = (int)lroundf((float)rect.x / density);
        rect.y = (int)lroundf((float)rect.y / density);
        rect.w = (int)lroundf((float)rect.w / density);
        rect.h = (int)lroundf((float)rect.h / density);
    }
    fosSetTextInputRect(controller, cmd, rect);
}

/// Routes SDL's view controller's setTextInputRect: through FOSSDLSetTextInputRect, once.
static void FOSSDLInstallTextInputRectFix(void) {
    Class cls = NSClassFromString(@"SDL_uikitviewcontroller");
    Method method = cls != Nil ? class_getInstanceMethod(cls, sel_registerName("setTextInputRect:")) : NULL;
    if (method == NULL || fosSetTextInputRect != NULL) {
        // An SDL without the on-screen keyboard's view lift, or already installed.
        return;
    }
    fosSetTextInputRect = (FOSSetTextInputRectIMP)method_setImplementation(method, (IMP)FOSSDLSetTextInputRect);
}

#pragma clang diagnostic pop

BOOL FOSSDLLoad(NSString *path, NSError *_Nullable *_Nullable error) {
    if (fosSDLLoaded) {
        return YES;
    }
    // The app links the same SDL3.framework, so dlopen hands back the image that is already loaded.
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    if (handle == NULL) {
        const char *reason = dlerror();
        if (error != NULL) {
            NSString *message =
                reason != NULL ? FOSStringFromUTF8(reason) : [NSString stringWithFormat:@"Can't open %@", path];
            *error = FOSSDLMakeError(1, message);
        }
        return NO;
    }
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    FOSSDLResolve(handle, missing);
    if (missing.count > 0) {
        if (error != NULL) {
            NSString *names = [missing componentsJoinedByString:@", "];
            *error = FOSSDLMakeError(2, [NSString stringWithFormat:@"SDL3 at %@ lacks %@", path, names]);
        }
        return NO;
    }
    fosSDLLoaded = YES;
    FOSSDLInstallTextInputRectFix();
    return YES;
}

int FOSSDLRunApp(int argc, char *_Nullable *_Nonnull argv, FOSSDLMainFunction mainFunction) {
    return fosSDL.RunApp(argc, argv, mainFunction, NULL);
}

BOOL FOSSDLSetHint(NSString *name, NSString *value) {
    return fosSDL.SetHint(name.UTF8String, value.UTF8String);
}

NSString *FOSSDLLastError(void) {
    const char *message = fosSDL.GetError();
    return message != NULL ? FOSStringFromUTF8(message) : @"";
}

/// Closes and detaches the virtual gamepad, if one is attached.
static void FOSSDLDetachVirtualGamepad(void) {
    if (fosGamepad != NULL) {
        fosSDL.CloseJoystick(fosGamepad);
        fosGamepad = NULL;
    }
    if (fosGamepadID != 0) {
        fosSDL.DetachVirtualJoystick(fosGamepadID);
        fosGamepadID = 0;
    }
    fosRumbleHandler = nil;
}

/// SDL_VirtualJoystickDesc.Rumble: forwards SDL's 16-bit strengths to the handler as 0...1.
static bool FOSSDLRumble(void *userdata, uint16_t low, uint16_t high) {
    (void)userdata;
    void (^handler)(float, float) = fosRumbleHandler;
    if (handler != nil) {
        handler((float)low / (float)UINT16_MAX, (float)high / (float)UINT16_MAX);
    }
    return true;
}

BOOL FOSSDLAttachVirtualGamepad(NSString *name, void (^_Nullable rumble)(float low, float high),
                                NSError *_Nullable *_Nullable error) {
    FOSSDLDetachVirtualGamepad();
    // SDL refcounts subsystems, so the game's own SDL_Init later adds to this rather than starting over.
    if (!fosSDL.InitSubSystem(FOSSDLInitJoystick | FOSSDLInitGamepad)) {
        if (error != NULL) {
            *error = FOSSDLMakeError(3, FOSSDLLastError());
        }
        return NO;
    }
    fosRumbleHandler = rumble;
    FOSSDLVirtualJoystickDesc desc;
    memset(&desc, 0, sizeof(desc));
    desc.version = (uint32_t)sizeof(desc);
    desc.type = FOSSDLJoystickTypeGamepad;
    desc.nbuttons = FOSSDLGamepadButtons;
    desc.naxes = FOSSDLGamepadAxes;
    desc.button_mask = (1U << FOSSDLGamepadButtons) - 1U;
    desc.axis_mask = (1U << FOSSDLGamepadAxes) - 1U;
    desc.name = name.UTF8String;  // SDL copies the name while attaching.
    desc.Rumble = FOSSDLRumble;
    uint32_t instanceID = fosSDL.AttachVirtualJoystick(&desc);
    FOSSDLJoystick *joystick = instanceID != 0 ? fosSDL.OpenJoystick(instanceID) : NULL;
    if (joystick == NULL) {
        if (error != NULL) {
            *error = FOSSDLMakeError(4, FOSSDLLastError());
        }
        if (instanceID != 0) {
            fosSDL.DetachVirtualJoystick(instanceID);
        }
        fosRumbleHandler = nil;
        return NO;
    }
    fosGamepadID = instanceID;
    fosGamepad = joystick;
    return YES;
}

void FOSSDLSetGamepadButton(NSInteger button, BOOL pressed) {
    if (fosGamepad != NULL && button >= 0 && button < FOSSDLGamepadButtons) {
        fosSDL.SetJoystickVirtualButton(fosGamepad, (int)button, pressed);
    }
}

void FOSSDLSetGamepadAxis(NSInteger axis, int16_t value) {
    if (fosGamepad != NULL && axis >= 0 && axis < FOSSDLGamepadAxes) {
        fosSDL.SetJoystickVirtualAxis(fosGamepad, (int)axis, value);
    }
}

/// Calls `body` with the game's first window; does nothing before the game has created one.
static void FOSSDLWithFirstWindow(void (^body)(FOSSDLWindow *window)) {
    int count = 0;
    FOSSDLWindow *_Nullable *_Nullable windows = fosSDL.GetWindows(&count);
    if (windows == NULL) {
        return;
    }
    FOSSDLWindow *first = count > 0 ? windows[0] : NULL;
    if (first != NULL) {
        body(first);
    }
    fosSDL.Free((void *)windows);
}

void FOSSDLWarpMouse(float x, float y) {
    FOSSDLWithFirstWindow(^(FOSSDLWindow *window) {
        // UIKit SDL has no WarpMouse of its own, so SDL turns this into a mouse-motion event at (x, y).
        fosSDL.WarpMouseInWindow(window, x, y);
    });
}

void FOSSDLScrollWheel(float notches) {
    FOSSDLWithFirstWindow(^(FOSSDLWindow *window) {
        FOSSDLEvent event;
        memset(&event, 0, sizeof(event));
        event.wheel.type = FOSSDLEventMouseWheel;
        event.wheel.windowID = fosSDL.GetWindowID(window);
        event.wheel.y = notches;
        long wholeNotches = lroundf(notches);
        event.wheel.integer_y = (int32_t)wholeNotches;
        fosSDL.GetMouseState(&event.wheel.mouse_x, &event.wheel.mouse_y);
        // SDL_PushEvent stamps the time when `timestamp` is 0.
        fosSDL.PushEvent(&event);
    });
}

/// The first text field in `view`'s hierarchy, searched breadth first.
static UITextField *_Nullable FOSSDLFindTextField(UIView *view) {
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:view];
    while (pending.count > 0) {
        UIView *next = pending.firstObject;
        [pending removeObjectAtIndex:0];
        if ([next isKindOfClass:[UITextField class]]) {
            return (UITextField *)next;
        }
        [pending addObjectsFromArray:next.subviews];
    }
    return nil;
}

/// SDL's hidden text field in the game's window: the first responder, holding the keyboard, while text input is on.
static UITextField *_Nullable FOSSDLTextField(void) {
    UIWindow *window = FOSSDLGameWindow();
    return window != nil ? FOSSDLFindTextField(window) : nil;
}

/// The text field whose keyboard the player hid, until it loses the focus; and the observer that watches for that.
static __weak UITextField *_Nullable fosKeyboardHiddenField = nil;
static id _Nullable fosEndEditingObserver = nil;

// The game turns SDL's text input on and off every frame to match its focused widget, so FactoriOS leaves text input
// alone and only swaps the text field's input view: an empty one hides the keyboard while the field keeps the focus.

void FOSSDLSetScreenKeyboardShown(BOOL shown) {
    UITextField *field = FOSSDLTextField();
    if (field == nil || !field.isFirstResponder) {
        // No text field of the game has the focus: nothing to type into.
        return;
    }
    field.inputView = shown ? nil : [[UIView alloc] initWithFrame:CGRectZero];
    [field reloadInputViews];
    if (shown) {
        fosKeyboardHiddenField = nil;
        return;
    }
    fosKeyboardHiddenField = field;
    if (fosEndEditingObserver == nil) {
        // The next text field the game focuses brings the keyboard back.
        fosEndEditingObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:UITextFieldTextDidEndEditingNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *notification) {
                        UITextField *ended = notification.object;
                        if (ended != nil && ended == fosKeyboardHiddenField) {
                            ended.inputView = nil;
                            fosKeyboardHiddenField = nil;
                        }
                    }];
    }
}

BOOL FOSSDLScreenKeyboardShown(void) {
    UITextField *field = FOSSDLTextField();
    return (BOOL)(field != nil && field.isFirstResponder && field.inputView == nil);
}

UIWindow *_Nullable FOSSDLGameWindow(void) {
    __block UIWindow *found = nil;
    FOSSDLWithFirstWindow(^(FOSSDLWindow *window) {
        uint32_t props = fosSDL.GetWindowProperties(window);
        // SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER: SDL keeps the UIWindow alive; this is an unretained reference.
        void *pointer = props != 0 ? fosSDL.GetPointerProperty(props, "SDL.window.uikit.window", NULL) : NULL;
        if (pointer != NULL) {
            found = (__bridge UIWindow *)pointer;
        }
    });
    return found;
}
