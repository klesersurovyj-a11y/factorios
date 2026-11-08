import FactoriOSCore
import UIKit

/// A view that takes no touches itself, only through its subviews: touches elsewhere reach the game's window below.
class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// The game's area: fingers on it become `TouchGestures` (cursor, A, X, B, zoom).
///
/// It fills the screen, so its points are screen points; the input turns them into the game window's, which may be
/// inset by the camera housing and the Frame margin. A mouse or trackpad isn't a finger: SDL reads it through
/// GameController's `GCMouse`, so its touches are ignored here.
final class GameTouchView: UIView {
    private let gestures: TouchGestures

    init(input: any GameInput) {
        gestures = TouchGestures(input: input)
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        // Built in code only, never from a storyboard.
        nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
        for touch in touches where touch.type == .direct {
            gestures.began(Self.id(of: touch), at: point(of: touch))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
        for touch in touches where touch.type == .direct {
            gestures.moved(Self.id(of: touch), to: point(of: touch))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
        for touch in touches where touch.type == .direct {
            gestures.ended(Self.id(of: touch), at: point(of: touch))
        }
    }

    override func touchesCancelled(_: Set<UITouch>, with _: UIEvent?) {
        gestures.cancelled()
    }

    /// Lets go of whatever the fingers hold: the app is leaving the screen.
    func cancel() {
        gestures.cancelled()
    }

    private func point(of touch: UITouch) -> PadPoint {
        let location = touch.location(in: self)
        return PadPoint(x: location.x, y: location.y)
    }

    /// A touch keeps its object from landing to lifting, which identifies it.
    static func id(of touch: UITouch) -> Int {
        ObjectIdentifier(touch).hashValue
    }
}
