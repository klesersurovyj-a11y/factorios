import Foundation

/// Fingers on the game (not on a control), in the game window's points, turned into the controller and cursor input
/// Factorio's controller mode understands.
///
/// Tap: moves the cursor there and taps A. Double tap and keep the finger down: holds A along the drag. Long press:
/// holds X, the cursor following the finger. Two-finger tap: B. Pinch: zoom, with Factorio's controller binding for it
/// (RT held while the D-pad taps up or down), as the game is in controller mode. Two-finger drag: scrolls (the
/// mouse wheel). A single-finger drag moves the cursor.
@MainActor
public final class TouchGestures {
    /// One finger until a second lands; then undecided, pinching or scrolling, and lifted once one of the two lifts.
    private enum Mode {
        case one
        case undecided
        case pinch
        case scroll
        case lifted
    }

    private static let longPress = Duration.milliseconds(300)
    private static let tapTime = Duration.milliseconds(300)
    private static let doubleTapTime = Duration.milliseconds(300)
    /// How far a finger moves before it's a drag, in points.
    private static let slop = 10.0
    /// How close the second tap of a double tap lands to the first, in points.
    private static let doubleTapSlop = 40.0
    /// Span ratio per notch of zoom.
    private static let zoomStep = 1.18
    /// Points of two-finger drag per notch of scrolling.
    private static let scrollStep = 36.0

    private let input: any GameInput
    private let presses: TimedPresses
    private let zoom: ControllerZoom
    private let clock = ContinuousClock()

    /// The fingers down, oldest first; the two oldest pinch and scroll.
    private var fingers: [Int] = []
    private var positions: [Int: PadPoint] = [:]
    private var down = PadPoint(x: 0, y: 0)
    private var held: PadButton?
    private var dragging = false
    private var lastTap: (at: ContinuousClock.Instant, point: PadPoint)?
    private var mode = Mode.one
    private var twoFingerStart = ContinuousClock.Instant.now
    private var spanReference = 0.0
    private var middleStart = PadPoint(x: 0, y: 0)
    private var scrollReference = 0.0
    private var longPressTask: Task<Void, Never>?

    /// Creates the gestures, sending to `input`.
    public init(input: any GameInput) {
        self.input = input
        presses = TimedPresses(input: input)
        zoom = ControllerZoom(input: input)
    }

    /// A finger lands at `point`.
    public func began(_ finger: Int, at point: PadPoint) {
        fingers.append(finger)
        positions[finger] = point
        if fingers.count == 1 {
            firstFingerDown(at: point)
        } else if fingers.count == 2, held == nil, mode == .one {
            secondFingerDown()
        }
    }

    /// A finger moves to `point`.
    public func moved(_ finger: Int, to point: PadPoint) {
        guard fingers.contains(finger) else {
            // A finger that landed before a cancel.
            return
        }
        positions[finger] = point
        if mode != .one {
            if fingers.count >= 2 {
                twoFingersMoved()
            }
            return
        }
        guard fingers.count == 1 else {
            // A third finger on its own does nothing.
            return
        }
        if held != nil || dragging {
            input.moveCursor(toX: Float(point.x), y: Float(point.y))
        } else if point.distance(to: down) > Self.slop {
            cancelLongPress()
            dragging = true
            input.moveCursor(toX: Float(point.x), y: Float(point.y))
        }
    }

    /// A finger lifts at `point`.
    public func ended(_ finger: Int, at point: PadPoint) {
        guard fingers.contains(finger) else {
            // A finger that landed before a cancel.
            return
        }
        positions[finger] = point
        if mode != .one {
            twoFingersLifted()
        } else if fingers.count == 1 {
            oneFingerLifted(at: point)
        }
        fingers.removeAll { $0 == finger }
        positions[finger] = nil
        if fingers.isEmpty {
            mode = .one
        }
    }

    /// The system took the touches (an alert, the app leaving the screen): let go of everything.
    public func cancelled() {
        cancelLongPress()
        zoom.cancel()
        releaseHeld()
        fingers = []
        positions = [:]
        dragging = false
        mode = .one
    }

    private func firstFingerDown(at point: PadPoint) {
        down = point
        dragging = false
        // The game shows what's under the finger.
        input.moveCursor(toX: Float(point.x), y: Float(point.y))
        let now = clock.now
        if let lastTap, now - lastTap.at < Self.doubleTapTime, point.distance(to: lastTap.point) < Self.doubleTapSlop {
            self.lastTap = nil
            hold(.south)
            return
        }
        longPressTask = Task { [weak self] in
            try? await Task.sleep(for: Self.longPress)
            guard !Task.isCancelled else {
                // The finger lifted or moved first.
                return
            }
            self?.longPressed()
        }
    }

    private func longPressed() {
        guard fingers.count == 1, held == nil, mode == .one, !dragging else {
            // The finger moved, lifted or became part of a two-finger gesture first.
            return
        }
        input.moveCursor(toX: Float(down.x), y: Float(down.y))
        hold(.west)
    }

    private func secondFingerDown() {
        cancelLongPress()
        mode = .undecided
        twoFingerStart = clock.now
        spanReference = span()
        middleStart = middle()
    }

    private func oneFingerLifted(at point: PadPoint) {
        cancelLongPress()
        if held != nil {
            releaseHeld()
        } else if !dragging {
            input.moveCursor(toX: Float(point.x), y: Float(point.y))
            presses.tap(.south)
            lastTap = (clock.now, point)
        }
        dragging = false
    }

    private func twoFingersLifted() {
        if mode == .undecided, clock.now - twoFingerStart < Self.tapTime {
            presses.tap(.east)
        }
        // So the other finger's lift doesn't tap again.
        mode = .lifted
    }

    private func twoFingersMoved() {
        let span = span()
        let middle = middle()
        if mode == .undecided {
            let threshold = 2 * Self.slop
            if abs(span - spanReference) > threshold {
                mode = .pinch
            } else if middle.distance(to: middleStart) > threshold {
                mode = .scroll
            } else {
                // Not far enough yet to tell a pinch from a scroll.
                return
            }
            spanReference = span
            scrollReference = middle.y
            // The map zooms round the cursor.
            input.moveCursor(toX: Float(middle.x), y: Float(middle.y))
        }
        if mode == .pinch, spanReference > 0, span > 0 {
            let steps = Int(log(span / spanReference) / log(Self.zoomStep))
            if steps != 0 {
                // Spreading the fingers zooms in.
                zoom.zoom(steps)
                spanReference *= pow(Self.zoomStep, Double(steps))
            }
        } else if mode == .scroll {
            let steps = Int((scrollReference - middle.y) / Self.scrollStep)
            if steps != 0 {
                // Fingers moving up scroll the content down, as everywhere on iOS.
                input.scroll(notches: Float(-steps))
                scrollReference -= Double(steps) * Self.scrollStep
            }
        }
    }

    /// The distance between the two oldest fingers.
    private func span() -> Double {
        guard fingers.count >= 2, let first = positions[fingers[0]], let second = positions[fingers[1]] else {
            return 0
        }
        return first.distance(to: second)
    }

    /// The point between the two oldest fingers.
    private func middle() -> PadPoint {
        guard fingers.count >= 2, let first = positions[fingers[0]], let second = positions[fingers[1]] else {
            return down
        }
        return PadPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
    }

    private func hold(_ button: PadButton) {
        presses.hold(button)
        held = button
    }

    private func releaseHeld() {
        if let held {
            presses.release(held)
        }
        held = nil
    }

    private func cancelLongPress() {
        longPressTask?.cancel()
        longPressTask = nil
    }
}

/// Button presses held at least three game ticks, so the game sees a quick tap.
@MainActor
private final class TimedPresses {
    static let minimumHold = Duration.milliseconds(50)

    private let input: any GameInput
    private let clock = ContinuousClock()
    private var pressedAt: [PadButton: ContinuousClock.Instant] = [:]
    private var releases: [PadButton: Task<Void, Never>] = [:]

    init(input: any GameInput) {
        self.input = input
    }

    func hold(_ button: PadButton) {
        // A release still waiting would end this hold.
        releases.removeValue(forKey: button)?.cancel()
        input.setButton(button, pressed: true)
        pressedAt[button] = clock.now
    }

    func release(_ button: PadButton) {
        let earliest = (pressedAt[button] ?? clock.now) + Self.minimumHold
        releases[button] = Task { [weak self] in
            try? await Task.sleep(until: earliest, clock: .continuous)
            guard !Task.isCancelled else {
                // Pressed again before the release was due.
                return
            }
            self?.input.setButton(button, pressed: false)
            self?.releases[button] = nil
        }
    }

    func tap(_ button: PadButton) {
        hold(button)
        release(button)
    }
}

/// Zooms with Factorio's controller binding: RT held while the D-pad taps up (in) or down (out), one tap a step.
///
/// Each change is held `TimedPresses.minimumHold` so the game sees RT down before the first tap and every tap apart.
@MainActor
private final class ControllerZoom {
    private let input: any GameInput
    /// Steps still to tap: positive zooms in.
    private var pending = 0
    private var task: Task<Void, Never>?

    init(input: any GameInput) {
        self.input = input
    }

    func zoom(_ steps: Int) {
        pending += steps
        guard task == nil else {
            // The running taps pick the new steps up.
            return
        }
        task = Task { [weak self] in
            await self?.tapPending()
        }
    }

    /// Lets go of RT and the D-pad and drops the steps not yet tapped.
    func cancel() {
        guard let task else {
            // Nothing held.
            return
        }
        task.cancel()
        self.task = nil
        pending = 0
        input.setButton(.dpadUp, pressed: false)
        input.setButton(.dpadDown, pressed: false)
        input.setAxis(.rightTrigger, value: 0)
    }

    private func tapPending() async {
        // A hold after RT goes down and after each tap: RT is down before the first tap, the taps stay apart, and
        // steps added meanwhile are seen before RT is let go.
        input.setAxis(.rightTrigger, value: 1)
        guard await hold() else {
            // cancel() released everything.
            return
        }
        while pending != 0 {
            let button: PadButton = pending > 0 ? .dpadUp : .dpadDown
            pending -= pending.signum()
            input.setButton(button, pressed: true)
            guard await hold() else {
                // cancel() released everything.
                return
            }
            input.setButton(button, pressed: false)
            guard await hold() else {
                // cancel() released everything.
                return
            }
        }
        input.setAxis(.rightTrigger, value: 0)
        task = nil
    }

    /// Waits one minimum hold; false when cancelled meanwhile.
    private func hold() async -> Bool {
        try? await Task.sleep(for: TimedPresses.minimumHold)
        return !Task.isCancelled
    }
}
