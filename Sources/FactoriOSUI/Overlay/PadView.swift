import FactoriOSCore
import UIKit

/// The on-screen controller: draws the controls and turns fingers on them into controller input, or, while the
/// layout editor is open, into moving and resizing them.
///
/// Touches anywhere but on a control fall through to the game below, except in the editor, which takes the screen.
final class PadView: UIView {
    /// The pad's state and placements; its `layout` is the one shown.
    let controller: PadController
    private var editor = PadLayoutEditor()

    /// The editor is open: the controls move instead of pressing.
    var isEditing = false {
        didSet {
            controller.releaseAll()
            editor = PadLayoutEditor()
            setNeedsDisplay()
        }
    }

    /// The controls step aside: a physical controller is in use, or Factorio is in keyboard-and-mouse mode.
    var stepsAside = false {
        didSet {
            if stepsAside {
                controller.releaseAll()
            }
            setNeedsDisplay()
        }
    }

    /// A control went down or was selected, for a haptic.
    var onFeedback: (PadFeedback) -> Void = { _ in
        // Set by the overlay; without it the pad plays no haptics.
    }

    /// The control the editor's tools act on.
    var selected: PadControlID? { editor.selected }

    /// Whether the controls are drawn and take touches.
    private var controlsShown: Bool {
        isEditing || (!stepsAside && !controller.layout.hidden)
    }

    init(input: (any GameInput)?, layout: PadLayout) {
        controller = PadController(input: input, layout: layout, geometry: PadGeometry(width: 0, height: 0))
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        // Built in code only, never from a storyboard.
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let geometry = PadGeometry(width: bounds.width, height: bounds.height)
        if geometry != controller.geometry {
            controller.releaseAll()
            controller.geometry = geometry
            setNeedsDisplay()
        }
    }

    override func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
        if isEditing {
            return bounds.contains(point)
        }
        guard controlsShown else {
            return false
        }
        return controller.geometry.control(at: Self.padPoint(point), in: controller.layout) != nil
    }

    /// Changes the layout, as the editor's tools do, and redraws.
    func updateLayout(_ change: (inout PadLayout, inout PadLayoutEditor) -> Void) {
        change(&controller.layout, &editor)
        alpha = controller.layout.opacity
        setNeedsDisplay()
    }

    /// Lets go of every control: the app is leaving the screen.
    func releaseAll() {
        controller.releaseAll()
        editor.releaseAll()
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
        for touch in touches {
            let point = Self.padPoint(touch.location(in: self))
            let id = GameTouchView.id(of: touch)
            if isEditing {
                if editor.touchBegan(id, at: point, layout: controller.layout, geometry: controller.geometry) {
                    onFeedback(.tick)
                }
            } else if let feedback = controller.touchBegan(id, at: point) {
                onFeedback(feedback)
            }
        }
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
        for touch in touches {
            let point = Self.padPoint(touch.location(in: self))
            let id = GameTouchView.id(of: touch)
            if isEditing {
                _ = editor.touchMoved(id, to: point, layout: &controller.layout, geometry: controller.geometry)
            } else {
                onFeedback(controller.touchMoved(id, to: point))
            }
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
        lift(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with _: UIEvent?) {
        lift(touches)
    }

    private func lift(_ touches: Set<UITouch>) {
        for touch in touches {
            let id = GameTouchView.id(of: touch)
            if isEditing {
                editor.touchEnded(id)
            } else {
                controller.touchEnded(id)
            }
        }
        setNeedsDisplay()
    }

    override func draw(_: CGRect) {
        guard controlsShown else {
            // The controls stepped aside or are hidden: nothing to draw.
            return
        }
        let layout = controller.layout
        let geometry = controller.geometry
        for control in layout.shownControls {
            let middle = geometry.center(of: control, in: layout)
            PadPainter.draw(
                control,
                state: controller.state(of: control),
                center: CGPoint(x: middle.x, y: middle.y),
                radius: geometry.radius(of: control, in: layout),
                selected: isEditing && control == editor.selected
            )
        }
    }

    private static func padPoint(_ point: CGPoint) -> PadPoint {
        PadPoint(x: point.x, y: point.y)
    }
}
