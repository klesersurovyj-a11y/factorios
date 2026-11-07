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
    private static let axisScale: Float = 32_767

    /// The SDL window's frame in screen points, once it is on screen; the overlay sends screen points.
    var gameWindowFrame: CGRect?

    /// Attaches the virtual gamepad; `haptics` plays the game's rumble, or nil for none.
    init(haptics: RumbleHaptics?) throws {
        let rumble: (@Sendable (Float, Float) -> Void)? = haptics.map { player in
            { low, high in
                Task { @MainActor in player.rumble(low: low, high: high) }
            }
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
        let lowest: Float
        switch axis {
        case .leftTrigger, .rightTrigger:
            lowest = 0
        case .leftX, .leftY, .rightX, .rightY:
            lowest = -1
        }
        let clamped = min(max(value, lowest), 1)
        FOSSDLSetGamepadAxis(axis.rawValue, Int16((clamped * Self.axisScale).rounded()))
    }

    func moveCursor(toX x: Float, y: Float) {
        var windowX = CGFloat(x)
        var windowY = CGFloat(y)
        if let frame = gameWindowFrame {
            // The game's window may be inset by the Frame margin; SDL wants points in the window.
            windowX = min(max(windowX - frame.minX, 0), frame.width)
            windowY = min(max(windowY - frame.minY, 0), frame.height)
        }
        FOSSDLWarpMouse(Float(windowX), Float(windowY))
    }

    func scroll(notches: Float) {
        FOSSDLScrollWheel(notches)
    }

    func setKeyboardVisible(_ visible: Bool) {
        FOSSDLSetTextInputActive(visible)
    }
}
