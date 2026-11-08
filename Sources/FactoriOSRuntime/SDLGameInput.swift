import CoreGraphics
import FactoriOSCompat
import FactoriOSCore
import Foundation

/// The game's input from the on-screen controls: a virtual SDL gamepad, the SDL mouse and SDL text input.
@MainActor
final class SDLGameInput: GameInput {
    /// The name the game shows for the on-screen controller.
    private static let gamepadName = "FactoriOS Controller"
    /// SDL's largest axis value.
    private static let axisMax: Float = 32_767
    /// SDL's smallest axis value: a released trigger.
    private static let axisMin: Float = -32_768

    /// The SDL window's frame in screen points, once it is on screen; the overlay sends screen points.
    var gameWindowFrame: CGRect?

    /// Attaches the virtual gamepad; `haptics` plays the game's rumble, or nil for none.
    init(haptics: RumbleHaptics?) throws {
        let rumble: (@Sendable (Float, Float) -> Void)?
        if let haptics {
            rumble = { low, high in
                Task { @MainActor in haptics.rumble(low: low, high: high) }
            }
        } else {
            rumble = nil
        }
        var error: NSError?
        guard FOSSDLAttachVirtualGamepad(Self.gamepadName, rumble, &error) else {
            throw GameLaunchError.gamepadUnavailable(error?.localizedDescription ?? FOSSDLLastError())
        }
    }

    func setButton(_ button: PadButton, pressed: Bool) {
        FOSSDLSetGamepadButton(button.rawValue, pressed)
    }

    func setAxis(_ axis: PadAxis, value: Float) {
        let raw: Float
        switch axis {
        case .leftTrigger, .rightTrigger:
            // SDL's gamepad maps a virtual trigger's whole range onto 0...1, so 0 here would be half pressed.
            let pressed = min(max(value, 0), 1)
            raw = Self.axisMin + pressed * (Self.axisMax - Self.axisMin)
        case .leftX, .leftY, .rightX, .rightY:
            raw = min(max(value, -1), 1) * Self.axisMax
        }
        FOSSDLSetGamepadAxis(axis.rawValue, Int16(raw.rounded()))
    }

    func moveCursor(toX x: Float, y: Float) {
        var windowX = CGFloat(x)
        var windowY = CGFloat(y)
        if let frame = gameWindowFrame {
            // The game's window is inset by the camera housing and the Frame margin; SDL wants points in the window.
            windowX = min(max(windowX - frame.minX, 0), frame.width)
            windowY = min(max(windowY - frame.minY, 0), frame.height)
        }
        FOSSDLWarpMouse(Float(windowX), Float(windowY))
    }

    func scroll(notches: Float) {
        FOSSDLScrollWheel(notches)
    }

    func setKeyboardVisible(_ visible: Bool) {
        FOSSDLSetScreenKeyboardShown(visible)
    }

    var isKeyboardVisible: Bool {
        FOSSDLScreenKeyboardShown()
    }
}
