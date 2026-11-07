/// The player's FactoriOS settings, applied to `config.ini` and the session each time the game starts.
public struct GameSettings: Codable, Equatable, Sendable {
    /// Factorio's sprite resolution setting (`graphics-quality`).
    public enum SpriteQuality: String, Codable, CaseIterable, Sendable {
        /// Full-resolution sprites.
        case high
        /// Half-resolution sprites: much less memory, for big saves or smaller devices.
        case medium
    }

    /// The frame-rate cap; the game keeps 60 updates a second either way.
    public enum FrameRate: Int, Codable, CaseIterable, Sendable {
        /// 30 frames a second: cooler and longer on battery.
        case thirty = 30
        /// 60 frames a second.
        case sixty = 60
    }

    /// The size of the margin round the game, which keeps rounded screen corners off its menus.
    public enum Frame: Int, Codable, CaseIterable, Sendable {
        /// No margin.
        case off = 0
        /// A thin margin.
        case thin = 10
        /// A wide margin.
        case wide = 20
    }

    /// The share of the screen's native pixels the game renders, in percent (100 is native).
    public var resolutionScale: Int
    /// The frame-rate cap.
    public var frameRate: FrameRate
    /// The margin round the game.
    public var frame: Frame
    /// Factorio's sprite resolution.
    public var spriteQuality: SpriteQuality
    /// Light graphics turn off smoke, clouds, decoratives, particles, shadows and terrain effects.
    public var lightGraphics: Bool
    /// Factorio's FPS/UPS counter in the top-left corner.
    public var fpsCounter: Bool
    /// Verbose logs: frame presentation, memory and every graphics error.
    public var detailedLogs: Bool
    /// Haptics for the game's rumble and the on-screen buttons.
    public var vibration: Bool

    /// Whether light graphics were applied at the last start, so turning them off restores the effects once.
    public var lightApplied: Bool

    /// The settings a fresh install starts with.
    public static let defaults = Self(
        resolutionScale: 100,
        frameRate: .sixty,
        frame: .off,
        spriteQuality: .high,
        lightGraphics: false,
        fpsCounter: false,
        detailedLogs: false,
        vibration: true,
        lightApplied: false
    )

    /// Resolution scales offered in Settings, in percent.
    public static let resolutionScales = [50, 67, 75, 100]
}
