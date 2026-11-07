// A bridge to the SDL3 bundled with FactoriOS, resolved at run time with dlsym.
//
// The game's static SDL3 forwards every call to this same library through SDL3_DYNAMIC_API, so whatever FactoriOS
// does here (hints, the virtual gamepad, mouse events) is what the game sees. No SDL headers are needed to build: the
// few SDL3 ABI pieces used are declared in FOSSDL.m.

#ifndef FACTORIOS_FOS_SDL_H
#define FACTORIOS_FOS_SDL_H

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

/// The error domain of FOSSDL failures; the description carries SDL's or dyld's message.
extern NSErrorDomain const FOSSDLErrorDomain;

/// The program entry SDL_RunApp calls on the main thread once UIKit has finished launching.
typedef int (*FOSSDLMainFunction)(int argc, char *_Nullable *_Nullable argv);

/// Loads the SDL3 library at `path` and resolves the functions the bridge uses. Call once before anything else.
BOOL FOSSDLLoad(NSString *path, NSError *_Nullable *_Nullable error);

/// Hands the process to SDL_RunApp: SDL runs UIApplicationMain and calls `mainFunction` from its app delegate.
int FOSSDLRunApp(int argc, char *_Nullable *_Nonnull argv, FOSSDLMainFunction mainFunction);

/// Calls SDL_SetMainReady, which lets SDL_Init succeed outside SDL's own main wrapper.
void FOSSDLSetMainReady(void);

/// Sets an SDL hint (SDL_SetHint); returns whether SDL accepted it.
BOOL FOSSDLSetHint(NSString *name, NSString *value);

/// The message of SDL's last error (SDL_GetError).
NSString *FOSSDLLastError(void);

/// Attaches a virtual gamepad with SDL's 15 standard buttons and 6 axes, numbered as SDL_GamepadButton and
/// SDL_GamepadAxis, and opens it so the bridge can drive it. `rumble` receives the game's rumble requests as low- and
/// high-frequency strengths from 0 to 1; both 0 means stop. It runs on whichever thread the game rumbles from.
BOOL FOSSDLAttachVirtualGamepad(NSString *name, void (NS_SWIFT_SENDABLE ^_Nullable rumble)(float low, float high),
                                NSError *_Nullable *_Nullable error);

/// Closes and detaches the virtual gamepad, if one is attached.
void FOSSDLDetachVirtualGamepad(void);

/// Presses or releases a button of the virtual gamepad (SDL_GamepadButton number).
void FOSSDLSetGamepadButton(NSInteger button, BOOL pressed);

/// Moves an axis of the virtual gamepad (SDL_GamepadAxis number) to an SDL axis value.
void FOSSDLSetGamepadAxis(NSInteger axis, int16_t value);

/// Moves the mouse cursor to a point, in points, of the game's first window (SDL_WarpMouseInWindow).
void FOSSDLWarpMouse(float x, float y);

/// Sends a vertical mouse-wheel event to the game's first window; positive notches scroll up.
void FOSSDLScrollWheel(float notches);

/// Starts or stops text input on the game's first window, which shows or hides the system keyboard.
void FOSSDLSetTextInputActive(BOOL active);

/// The UIWindow behind the game's first SDL window, read from its SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER property
/// ("SDL.window.uikit.window"); nil before the game has created a window or when SDL doesn't set the property.
UIWindow *_Nullable FOSSDLGameWindow(void);

/// Whether the game has created at least one SDL window.
BOOL FOSSDLHasWindow(void);

NS_ASSUME_NONNULL_END

#endif  // FACTORIOS_FOS_SDL_H
