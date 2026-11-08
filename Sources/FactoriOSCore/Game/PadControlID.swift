/// One of the on-screen controller's controls.
///
/// Raw values are the keys in the saved layout. Cases are in draw order: a later control is drawn on top and wins
/// a touch.
public enum PadControlID: String, CaseIterable, Codable, Sendable {
    /// The left stick: walking.
    case leftStick = "LS"
    /// The D-pad.
    case dpad = "DPAD"
    /// Y: inventory and crafting. The largest after A, since it's used most after A.
    case buttonY = "Y"
    /// A: build, open, craft, pick up.
    case buttonA = "A"
    /// X: mine. Smaller, since a long press on the game mines too.
    case buttonX = "X"
    /// B: close, back. Smaller, since a two-finger tap presses it too.
    case buttonB = "B"
    /// LB: the quick panel while held.
    case leftShoulder = "LB"
    /// LT.
    case leftTrigger = "LT"
    /// RB: shoot.
    case rightShoulder = "RB"
    /// RT.
    case rightTrigger = "RT"
    /// The View button: the map.
    case view = "VIEW"
    /// The Menu button: the game menu.
    case menu = "MENU"
    /// The right stick: the cursor.
    case rightStick = "RS"
    /// Left stick click.
    case leftStickClick = "L3"
    /// Right stick click: a cursor next to the player.
    case rightStickClick = "R3"
}

/// A stick's two axes.
public struct PadStick: Equatable, Sendable {
    /// Across: -1 is left.
    public let x: PadAxis
    /// Down: -1 is up.
    public let y: PadAxis
}

/// What a control is and what it sends to the game.
public enum PadControlKind: Equatable, Sendable {
    /// A stick sending two axes.
    case stick(PadStick)
    /// The D-pad: four buttons, two at a time on the diagonals.
    case dpad
    /// A button.
    case button(PadButton)
    /// A trigger: an axis fully pressed or released.
    case trigger(PadAxis)

    /// How far from its middle a touch still lands on the control, in radii (pills have their own reach).
    public var reach: Double {
        switch self {
        case .stick:
            1.3
        case .dpad:
            1.15
        case .button, .trigger:
            1.2
        }
    }

    /// Sticks and the D-pad follow the finger; buttons and triggers don't.
    public var follows: Bool {
        switch self {
        case .stick, .dpad:
            true
        case .button, .trigger:
            false
        }
    }
}

/// The corner of the screen a control's position is measured from.
///
/// Both are fractions of the room the layout frame leaves across and down the screen.
public struct PadAnchor: Equatable, Sendable {
    /// 0 is the left edge, 1 the right.
    public let across: Double
    /// 0 is the top edge, 1 the bottom.
    public let down: Double
}

/// A control's fixed facts: what it sends, where it starts and how big it is.
struct PadControlSpec {
    /// What it sends.
    let kind: PadControlKind
    /// Its middle at the start, across the layout frame.
    let x: Double
    /// Its middle at the start, down the layout frame.
    let y: Double
    /// Its diameter (a pill's height), as a fraction of the frame's height.
    let size: Double
}

extension PadControlID {
    /// The control's fixed facts.
    ///
    /// Shoulders, triggers, stick clicks and Map/Menu mirror each other: x and 1 - x at the same height.
    var spec: PadControlSpec {
        switch self {
        case .leftStick:
            PadControlSpec(kind: .stick(PadStick(x: .leftX, y: .leftY)), x: 0.10, y: 0.70, size: 0.28)
        case .dpad:
            PadControlSpec(kind: .dpad, x: 0.245, y: 0.88, size: 0.20)
        case .buttonY:
            PadControlSpec(kind: .button(.north), x: 0.885, y: 0.635, size: 0.125)
        case .buttonA:
            PadControlSpec(kind: .button(.south), x: 0.885, y: 0.895, size: 0.13)
        case .buttonX:
            PadControlSpec(kind: .button(.west), x: 0.827, y: 0.765, size: 0.115)
        case .buttonB:
            PadControlSpec(kind: .button(.east), x: 0.943, y: 0.765, size: 0.115)
        case .leftShoulder:
            PadControlSpec(kind: .button(.leftShoulder), x: 0.075, y: 0.42, size: 0.10)
        case .leftTrigger:
            PadControlSpec(kind: .trigger(.leftTrigger), x: 0.17, y: 0.42, size: 0.085)
        case .rightShoulder:
            PadControlSpec(kind: .button(.rightShoulder), x: 0.83, y: 0.42, size: 0.085)
        case .rightTrigger:
            PadControlSpec(kind: .trigger(.rightTrigger), x: 0.925, y: 0.42, size: 0.10)
        case .view:
            PadControlSpec(kind: .button(.back), x: 0.4715, y: 0.26, size: 0.085)
        case .menu:
            PadControlSpec(kind: .button(.start), x: 0.5285, y: 0.26, size: 0.085)
        case .rightStick:
            PadControlSpec(kind: .stick(PadStick(x: .rightX, y: .rightY)), x: 0.64, y: 0.74, size: 0.24)
        case .leftStickClick:
            PadControlSpec(kind: .button(.leftStick), x: 0.215, y: 0.56, size: 0.085)
        case .rightStickClick:
            PadControlSpec(kind: .button(.rightStick), x: 0.785, y: 0.56, size: 0.085)
        }
    }

    /// What the control sends.
    public var kind: PadControlKind { spec.kind }

    /// The control's diameter (a pill's height) at scale 1, as a fraction of the layout frame's height.
    public var size: Double { spec.size }

    /// Shoulders and triggers are pills, twice as wide as high.
    public var isPill: Bool {
        [.leftShoulder, .leftTrigger, .rightShoulder, .rightTrigger].contains(self)
    }

    /// The text on the control; Map and Menu show icons instead, and the D-pad its arrows.
    public var label: String {
        switch self {
        case .leftStick:
            "L"
        case .rightStick:
            "R"
        case .dpad, .view, .menu:
            ""
        default:
            rawValue
        }
    }

    /// The control's name in the layout editor's list of controls to add back.
    public var name: String {
        switch self {
        case .leftStick:
            "L stick"
        case .rightStick:
            "R stick"
        case .dpad:
            "D-pad"
        case .view:
            "Map"
        case .menu:
            "Menu"
        default:
            rawValue
        }
    }

    /// The top middle for Map and Menu, which sit under the toolbar, otherwise the bottom corner on the control's side.
    public var anchor: PadAnchor {
        if spec.y < 0.3 {
            return PadAnchor(across: 0.5, down: 0)
        }
        return PadAnchor(across: spec.x < 0.5 ? 0 : 1, down: 1)
    }
}
