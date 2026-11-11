import FactoriOSCore
import Foundation

/// The player's FactoriOS settings, applied to `config.ini` and the session each time the game starts.
struct GameSettings: Codable, Equatable, Sendable {
    /// Factorio's sprite resolution setting (`graphics-quality`).
    enum SpriteQuality: String, Codable, CaseIterable, Sendable {
        /// Full-resolution sprites. On iPhone GPUs, which lack BC compression, their textures need about 4.3 GB; an
        /// iPhone 14 gives an app about 3.2 GB, so iOS ends the game while it loads.
        case high
        /// Half-resolution sprites: about a quarter of the memory, which fits iPhones.
        case medium
    }

    /// The frame-rate cap; the game keeps 60 updates a second either way.
    enum FrameRate: Int, Codable, CaseIterable, Sendable {
        /// 30 frames a second: cooler and longer on battery.
        case thirty = 30
        /// 60 frames a second.
        case sixty = 60
    }

    /// The size of the margin round the game, which keeps rounded screen corners off its menus.
    enum Frame: Int, Codable, CaseIterable, Sendable {
        /// No margin.
        case off = 0
        /// A thin margin.
        case thin = 10
        /// A wide margin.
        case wide = 20
    }

    /// Factorio's UI size, named for the monitor it matches: the UI takes as much of the screen as it does of a
    /// monitor this many pixels high at Factorio's 100%.
    enum UIScale: Int, Codable, CaseIterable, Sendable {
        /// As on a 720-pixel monitor, the smallest Factorio supports: the largest UI.
        case large = 720
        /// As on a 900-pixel monitor.
        case medium = 900
        /// As on a 1080-pixel monitor: the smallest UI, with the most of the game in view.
        case small = 1_080

        /// Factorio's pixel UI scale (`custom-ui-scale`) for a game `pixelHeight` pixels high, to two decimals.
        func pixelScale(forHeight pixelHeight: Int) -> Double {
            (Double(pixelHeight) / Double(rawValue) * 100).rounded() / 100
        }
    }

    /// The frame-rate cap.
    var frameRate: FrameRate
    /// The margin round the game.
    var frame: Frame
    /// Factorio's UI size.
    var uiScale: UIScale
    /// Factorio's sprite resolution.
    var spriteQuality: SpriteQuality
    /// Light graphics turn off smoke, clouds, decoratives, particles, shadows and terrain effects.
    var lightGraphics: Bool
    /// FactoriOS's overlay FPS label, counted from presented frames (not Factorio's FPS/UPS counter).
    var fpsCounter: Bool
    /// Turns on Metal's validation layer (`MTL_DEBUG_LAYER`) and verbose SDL logging.
    var detailedLogs: Bool
    /// Haptics for the game's rumble and the on-screen buttons.
    var vibration: Bool

    /// Whether light graphics were applied at the last start, so turning them off restores the effects once.
    var lightApplied: Bool

    /// The settings a fresh install starts with.
    static let defaults = Self(
        frameRate: .sixty,
        frame: .off,
        uiScale: .large,
        spriteQuality: .medium,
        lightGraphics: false,
        fpsCounter: false,
        detailedLogs: false,
        vibration: true,
        lightApplied: false
    )

    /// The settings saved in `file`, or the defaults when nothing was saved yet or the file can't be read (it's from a
    /// different version).
    static func load(from file: URL) -> Self {
        readJSON(from: file) ?? .defaults
    }

    /// Saves the settings to `file`, replacing it in one step.
    func save(to file: URL) throws {
        try writeJSON(to: file)
    }
}
