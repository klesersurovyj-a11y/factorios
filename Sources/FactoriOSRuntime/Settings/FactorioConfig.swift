import FactoriOSCore
import Foundation

/// Writes FactoriOS's settings into Factorio's `config.ini`; the player's other settings stay as they are.
enum FactorioConfig {
    /// What the config depends on about the device the game starts on.
    struct Device: Sendable {
        /// Whether a keyboard and mouse are connected, which puts Factorio in keyboard-and-mouse mode.
        var keyboardAndMouse: Bool
        /// Whether the GPU samples BC-compressed textures.
        var supportsBCTextures: Bool
        /// The screen's height sideways (its short side) in pixels, which the UI scale is measured in.
        var screenHeight: Int
    }

    /// Without its version header Factorio calls the file invalid and offers to reset it.
    private static let versionHeader = "; version=13"
    /// The effects light graphics turn off; Factorio has them all on by default.
    private static let effects = [
        "show-smoke", "show-clouds", "show-fog", "show-space-dust", "show-decoratives", "show-particles",
        "show-item-shadows", "show-inserter-shadows", "additional-terrain-effects", "high-quality-terrain",
        "elevated-rail-shadows",
    ]

    /// Returns `ini` with FactoriOS's keys set: paths, input method, native resolution, UI scale, sprite quality,
    /// effects and, on GPUs without BC formats, texture compression.
    ///
    /// The FPS counter is an app overlay fed by the runtime's Metal presentation hook, not a `config.ini` key.
    ///
    /// - Parameters:
    ///   - ini: The current `config.ini` text, empty when there is none yet.
    ///   - paths: Where the game's data and the player's folder are.
    ///   - settings: The player's settings.
    ///   - device: The device the game starts on.
    /// - Returns: The updated text.
    static func update(_ ini: String, paths: GamePaths, settings: GameSettings, device: Device) -> String {
        var config = ini.hasPrefix("; version=") ? ini : versionHeader + "\n" + ini
        // Factorio derives its paths from its executable, which here is FactoriOS, so name them.
        config = set(config, section: "path", key: "read-data", value: paths.gameData.path)
        config = set(config, section: "path", key: "write-data", value: paths.writeData.path)
        // Factorio doesn't switch between mouse and controller by itself.
        let method = device.keyboardAndMouse ? "keyboard-and-mouse" : "game-controller"
        config = set(config, section: "input", key: "input-method", value: method)
        // Without native resolution Factorio draws at the window's size in points, a third of an iPhone's pixels, and
        // upscales: text at a UI scale small enough to show the game is a blur.
        config = set(config, section: "graphics", key: "render-in-native-resolution", value: "true")
        // The UI scale is FactoriOS's setting: Factorio's own choice in its menu lasts until the next start.
        config = set(config, section: "interface", key: "ui-scale-mode", value: "manual-pixels")
        let scale = settings.uiScale.pixelScale(forHeight: device.screenHeight)
        config = set(config, section: "interface", key: "custom-ui-scale", value: String(scale))
        config = set(config, section: "graphics", key: "graphics-quality", value: settings.spriteQuality.rawValue)
        if let shown = effectsValue(light: settings.lightGraphics, lightApplied: settings.lightApplied) {
            for key in effects {
                config = set(config, section: "graphics", key: key, value: shown)
            }
        }
        // Factorio compresses sprites to BC, which iPhone GPUs lack: FactoriOS's Metal fixes decode BC on the CPU, so
        // compression would save no memory, and GPU-accelerated compression writes BC data the CPU never sees.
        if !device.supportsBCTextures {
            config = set(config, section: "graphics", key: "texture-compression-level", value: "none")
            config = set(config, section: "graphics", key: "gpu-accelerated-compression", value: "false")
        }
        return config
    }

    /// Updates `paths.config` for the next start.
    ///
    /// - Parameters:
    ///   - paths: Where `config.ini` and the game's data are.
    ///   - settings: The player's settings.
    ///   - device: The device the game starts on.
    /// - Returns: `settings` with `lightApplied` recording what was written; the caller saves it.
    /// - Throws: The file system's error when `config.ini` can't be read or written.
    static func write(paths: GamePaths, settings: GameSettings, device: Device) throws -> GameSettings {
        let file = paths.config
        let old: String
        if FileManager.default.fileExists(atPath: file.path) {
            old = try String(contentsOf: file, encoding: .utf8)
        } else {
            old = ""
        }
        let config = update(old, paths: paths, settings: settings, device: device)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(config.utf8).write(to: file, options: .atomic)
        var applied = settings
        applied.lightApplied = settings.lightGraphics
        return applied
    }

    /// The value for the effects keys: light turns them off at every start; turning Light off turns them back on
    /// once, and after that the game's own menu decides (`nil`).
    static func effectsValue(light: Bool, lightApplied: Bool) -> String? {
        light || lightApplied ? String(!light) : nil
    }

    /// Sets `key` in `section`, adding either where missing.
    static func set(_ ini: String, section: String, key: String, value: String) -> String {
        let entry = "\(key)=\(value)"
        var all = lines(of: ini)
        guard let header = all.firstIndex(of: "[\(section)]") else {
            var trimmed = Substring(ini)
            while trimmed.hasSuffix("\n") || trimmed.hasSuffix("\r") {
                trimmed = trimmed.dropLast()
            }
            return trimmed + "\n\n[\(section)]\n\(entry)\n"
        }
        let bodyStart = header + 1
        let end = all[bodyStart...].firstIndex { $0.hasPrefix("[") } ?? all.count
        if let existing = all[bodyStart..<end].firstIndex(where: { $0.hasPrefix(key + "=") }) {
            all[existing] = entry
        } else {
            all.insert(entry, at: bodyStart)
        }
        return all.joined(separator: "\n")
    }

    /// The lines of `ini`, without a Windows line end's carriage return (Factorio reads both).
    private static func lines(of ini: String) -> [String] {
        ini.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
    }
}
