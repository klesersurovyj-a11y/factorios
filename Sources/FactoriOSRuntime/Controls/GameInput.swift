/// A button of the controller the game sees: the on-screen pad and touch gestures press these.
///
/// Raw values are SDL3's `SDL_GamepadButton` numbers, so the bridge passes them through unchanged.
enum PadButton: Int, CaseIterable, Codable, Sendable {
    /// Build, open, craft, pick up.
    case south = 0
    /// Close, back, empty the hand.
    case east = 1
    /// Mine, craft 5.
    case west = 2
    /// Inventory and crafting.
    case north = 3
    /// The map.
    case back = 4
    /// The guide button; it fills the SDL gamepad's button slots, but no control sends it.
    case guide = 5
    /// The game menu.
    case start = 6
    /// Left stick click.
    case leftStick = 7
    /// Right stick click: a cursor next to the player that the right stick moves.
    case rightStick = 8
    /// LB: the quick panel while held.
    case leftShoulder = 9
    /// RB: shoot.
    case rightShoulder = 10
    /// D-pad up: details on the map.
    case dpadUp = 11
    /// D-pad down: picks up items.
    case dpadDown = 12
    /// D-pad left.
    case dpadLeft = 13
    /// D-pad right: rotates.
    case dpadRight = 14
}

/// An analog control of the game's controller.
///
/// Raw values are SDL3's `SDL_GamepadAxis` numbers.
enum PadAxis: Int, CaseIterable, Codable, Sendable {
    /// Left stick, horizontal: walking.
    case leftX = 0
    /// Left stick, vertical.
    case leftY = 1
    /// Right stick, horizontal: the cursor.
    case rightX = 2
    /// Right stick, vertical.
    case rightY = 3
    /// LT.
    case leftTrigger = 4
    /// RT.
    case rightTrigger = 5
}

/// What the on-screen controls and gestures send to the running game.
@MainActor
protocol GameInput: AnyObject {
    /// Presses or releases a controller button.
    func setButton(_ button: PadButton, pressed: Bool)
    /// Moves an axis; sticks run from -1 to 1, triggers from 0 to 1.
    func setAxis(_ axis: PadAxis, value: Float)
    /// Moves the game's mouse cursor to a point in the game window, in points.
    func moveCursor(toX x: Float, y: Float)
    /// Scrolls the mouse wheel by whole notches; positive is up.
    func scroll(notches: Float)
    /// Shows or hides the system keyboard for the game's focused text field; does nothing when none is focused.
    func setKeyboardVisible(_ visible: Bool)
    /// Whether the system keyboard is up for the game's focused text field.
    var isKeyboardVisible: Bool { get }
}
