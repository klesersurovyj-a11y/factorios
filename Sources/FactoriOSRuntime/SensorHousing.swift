public import UIKit

/// The camera housing (notch or Dynamic Island) at one end of the screen, which the game and the controls keep off.
@MainActor
public enum SensorHousing {
    /// The inset off the screen edge with the housing, read from the window's safe area.
    ///
    /// Zero where there is none (an iPad, an iPhone without one) or in portrait. iOS reports the housing's safe area
    /// on both sides in landscape; only the side with the camera gives it up.
    public static func insets(of window: UIWindow) -> UIEdgeInsets {
        let depth = max(window.safeAreaInsets.left, window.safeAreaInsets.right)
        switch window.windowScene?.effectiveGeometry.interfaceOrientation {
        case .landscapeRight:
            // The home end is on the right, so the camera is on the left.
            return UIEdgeInsets(top: 0, left: depth, bottom: 0, right: 0)
        case .landscapeLeft:
            return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: depth)
        default:
            return .zero
        }
    }
}
