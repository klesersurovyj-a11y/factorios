/// The layout editor's touches: one finger drags a control, two pinch it, a tap selects it for the editor's tools.
public struct PadLayoutEditor: Sendable {
    /// A finger on a control, and where it was last.
    private struct Drag: Sendable {
        let control: PadControlID
        var last: PadPoint
    }

    /// The control the editor's tools (remove, smaller, bigger) act on.
    public private(set) var selected: PadControlID?
    private var drags: [Int: Drag] = [:]
    private var pinchStartDistance = 0.0
    private var pinchStartScale = 1.0

    /// Creates an editor with nothing selected.
    public init() {
        // Nothing is selected and no finger is down until the player touches a control.
    }

    /// A finger lands; on a control it selects it and starts dragging, a second finger on it starts a pinch.
    ///
    /// - Returns: Whether the selection changed, for a haptic.
    public mutating func touchBegan(
        _ touch: Int, at point: PadPoint, layout: PadLayout, geometry: PadGeometry
    ) -> Bool {
        guard let control = geometry.control(at: point, in: layout) else {
            let changed = selected != nil
            selected = nil
            return changed
        }
        if let other = drags.first(where: { $0.value.control == control && $0.key != touch }) {
            pinchStartDistance = point.distance(to: other.value.last)
            pinchStartScale = layout.placement(of: control).scale
        }
        drags[touch] = Drag(control: control, last: point)
        let changed = selected != control
        selected = control
        return changed
    }

    /// A finger moves: drags its control, or resizes it when two fingers hold it.
    ///
    /// - Returns: Whether the layout changed.
    public mutating func touchMoved(
        _ touch: Int, to point: PadPoint, layout: inout PadLayout, geometry: PadGeometry
    ) -> Bool {
        guard var drag = drags[touch] else {
            // A finger that landed off the controls.
            return false
        }
        let previous = drag.last
        drag.last = point
        drags[touch] = drag
        let partner = drags.first { $0.value.control == drag.control && $0.key != touch }
        if let partner {
            let span = point.distance(to: partner.value.last)
            if pinchStartDistance > 0 {
                layout.setScale(pinchStartScale * span / pinchStartDistance, of: drag.control)
            }
        } else {
            let middle = geometry.center(of: drag.control, in: layout)
            let target = PadPoint(x: middle.x + point.x - previous.x, y: middle.y + point.y - previous.y)
            geometry.move(drag.control, to: target, in: &layout)
        }
        return true
    }

    /// A finger lifts.
    public mutating func touchEnded(_ touch: Int) {
        drags[touch] = nil
    }

    /// Forgets every finger, keeping the selection.
    public mutating func releaseAll() {
        drags = [:]
    }

    /// Selects `control`, as after adding it back.
    public mutating func select(_ control: PadControlID?) {
        selected = control
    }

    /// Removes the selected control from the screen.
    public mutating func removeSelected(from layout: inout PadLayout) {
        guard let selected else {
            // Nothing selected: the tool does nothing.
            return
        }
        layout.remove(selected)
        drags = drags.filter { $0.value.control != selected }
        self.selected = nil
    }

    /// Makes the selected control a step bigger (positive `steps`) or smaller.
    public func resizeSelected(by steps: Int, in layout: inout PadLayout) {
        guard let selected else {
            // Nothing selected: the tool does nothing.
            return
        }
        let scale = layout.placement(of: selected).scale + Double(steps) * PadLayout.scaleStep
        layout.setScale(scale, of: selected)
    }
}
