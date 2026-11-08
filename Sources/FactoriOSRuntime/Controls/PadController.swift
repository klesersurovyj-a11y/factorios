/// What a touch on the pad did, for the haptic that goes with it.
enum PadFeedback: Equatable, Sendable {
    /// Nothing went down.
    case silent
    /// A D-pad direction went down.
    case tick
    /// A button or trigger went down.
    case click
}

/// A stick's two axis values.
struct StickValue: Equatable, Sendable {
    /// Released.
    static let center = Self(x: 0, y: 0)

    var x: Float
    var y: Float
}

/// A control's live state, for drawing it.
struct PadControlState: Equatable, Sendable {
    /// The touches on it, oldest first: the oldest drives a stick or the D-pad.
    var touches: [Int] = []
    /// A held stick's well, where its finger landed; `nil` takes the finger's next position.
    var origin: PadPoint?
    /// A held stick's knob.
    var knob: PadPoint?
    /// The D-pad directions held.
    var directions: Set<PadButton> = []
    /// The axis values last sent for a stick.
    var sent = StickValue.center

    /// Whether a finger is on it.
    var isPressed: Bool { !touches.isEmpty }
}

/// Turns touches on the on-screen controls into controller input for the game.
@MainActor
final class PadController {
    /// The D-pad's middle presses nothing: this part of its radius.
    private static let dpadDeadZone = 0.2
    /// sin 22.5°: where a straight direction meets a diagonal.
    private static let diagonal = 0.38

    private let input: (any GameInput)?
    /// The controls' placements.
    var layout: PadLayout
    /// Where the controls are on screen.
    var geometry: PadGeometry
    /// The live state of every control a finger is on, or was on.
    private(set) var states: [PadControlID: PadControlState] = [:]
    private var touched: [Int: PadControlID] = [:]

    /// Creates a pad that sends to `input`; without one (the layout preview in Settings) it sends nothing.
    init(input: (any GameInput)?, layout: PadLayout, geometry: PadGeometry) {
        self.input = input
        self.layout = layout
        self.geometry = geometry
    }

    /// The state of `control`.
    func state(of control: PadControlID) -> PadControlState {
        states[control] ?? PadControlState()
    }

    /// A finger lands on the pad.
    ///
    /// - Returns: `nil` when it isn't on a control, otherwise the haptic to play.
    func touchBegan(_ touch: Int, at point: PadPoint) -> PadFeedback? {
        guard let control = geometry.control(at: point, in: layout) else {
            // Not on a control: the touch is the game's.
            return nil
        }
        touched[touch] = control
        var state = state(of: control)
        guard !state.touches.contains(touch) else {
            return .silent
        }
        state.touches.append(touch)
        states[control] = state
        guard state.touches.count == 1 else {
            return .silent
        }
        switch control.kind {
        case .stick:
            state.origin = point
            state.knob = point
            states[control] = state
            return .silent
        case .dpad:
            return aim(control, at: point) ? .tick : .silent
        case .button(let button):
            input?.setButton(button, pressed: true)
            return .click
        case .trigger(let axis):
            input?.setAxis(axis, value: 1)
            return .click
        }
    }

    /// A finger on the pad moves.
    ///
    /// - Returns: The haptic to play.
    func touchMoved(_ touch: Int, to point: PadPoint) -> PadFeedback {
        guard let control = touched[touch], state(of: control).touches.first == touch else {
            return .silent
        }
        switch control.kind {
        case .stick(let stick):
            moveKnob(control, stick: stick, to: point)
            return .silent
        case .dpad:
            return aim(control, at: point) ? .tick : .silent
        case .button, .trigger:
            return .silent
        }
    }

    /// A finger lifts or is cancelled.
    func touchEnded(_ touch: Int) {
        guard let control = touched.removeValue(forKey: touch) else {
            // A touch that never landed on a control.
            return
        }
        var state = state(of: control)
        let wasFirst = state.touches.first == touch
        state.touches.removeAll { $0 == touch }
        states[control] = state
        let handOver = !state.touches.isEmpty && wasFirst && control.kind.follows
        guard state.touches.isEmpty || handOver else {
            // Another finger still holds the button.
            return
        }
        // Let go, or handed over to the finger still resting on it, recentred where that finger is next.
        release(control)
    }

    /// Lets go of everything: the pad steps aside, the editor opens, or the game goes to the background.
    func releaseAll() {
        for control in states.keys {
            states[control]?.touches = []
            release(control)
        }
        touched = [:]
    }

    private func release(_ control: PadControlID) {
        var state = state(of: control)
        switch control.kind {
        case .stick(let stick):
            if state.sent != .center {
                input?.setAxis(stick.x, value: 0)
                input?.setAxis(stick.y, value: 0)
            }
            state.sent = .center
        case .dpad:
            for button in state.directions {
                input?.setButton(button, pressed: false)
            }
            state.directions = []
        case .button(let button):
            input?.setButton(button, pressed: false)
        case .trigger(let axis):
            input?.setAxis(axis, value: 0)
        }
        state.origin = nil
        state.knob = nil
        states[control] = state
    }

    /// Moves the knob to the finger, within the stick's radius of its well, and sends its offset.
    private func moveKnob(_ control: PadControlID, stick: PadStick, to point: PadPoint) {
        var state = state(of: control)
        let origin = state.origin ?? point
        let radius = max(geometry.radius(of: control, in: layout), 1)
        var dx = point.x - origin.x
        var dy = point.y - origin.y
        let distance = point.distance(to: origin)
        if distance > radius {
            dx *= radius / distance
            dy *= radius / distance
        }
        state.origin = origin
        state.knob = PadPoint(x: origin.x + dx, y: origin.y + dy)
        let value = StickValue(x: Float(dx / radius), y: Float(dy / radius))
        if value.x != state.sent.x {
            input?.setAxis(stick.x, value: value.x)
        }
        if value.y != state.sent.y {
            input?.setAxis(stick.y, value: value.y)
        }
        state.sent = value
        states[control] = state
    }

    /// Holds the D-pad directions toward `point`.
    ///
    /// - Returns: Whether a direction went down.
    private func aim(_ control: PadControlID, at point: PadPoint) -> Bool {
        let middle = geometry.center(of: control, in: layout)
        let distance = point.distance(to: middle)
        var wanted: Set<PadButton> = []
        if distance > geometry.radius(of: control, in: layout) * Self.dpadDeadZone {
            let across = (point.x - middle.x) / distance
            let down = (point.y - middle.y) / distance
            if down < -Self.diagonal { wanted.insert(.dpadUp) }
            if down > Self.diagonal { wanted.insert(.dpadDown) }
            if across < -Self.diagonal { wanted.insert(.dpadLeft) }
            if across > Self.diagonal { wanted.insert(.dpadRight) }
        }
        var state = state(of: control)
        for button in state.directions.subtracting(wanted) {
            input?.setButton(button, pressed: false)
        }
        let pressed = wanted.subtracting(state.directions)
        for button in pressed {
            input?.setButton(button, pressed: true)
        }
        state.directions = wanted
        states[control] = state
        return !pressed.isEmpty
    }
}
