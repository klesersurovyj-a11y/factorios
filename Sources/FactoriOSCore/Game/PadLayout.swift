public import Foundation

/// Where the player put the on-screen controls, which ones show, and how see-through they are.
public struct PadLayout: Codable, Sendable, Equatable {
    /// A control's place and size.
    public struct Placement: Codable, Sendable, Equatable {
        /// Its middle across the layout frame, from 0 (left) to 1 (right).
        public var x: Double
        /// Its middle down the layout frame, from 0 (top) to 1 (bottom).
        public var y: Double
        /// Its size relative to the default, within `PadLayout.scales`.
        public var scale: Double
        /// Whether it's on screen; removed controls can be added back in the editor.
        public var shown: Bool

        /// Creates a placement.
        public init(x: Double, y: Double, scale: Double, shown: Bool) {
            self.x = x
            self.y = y
            self.scale = scale
            self.shown = shown
        }

        /// Where `control` starts out.
        public static func initial(for control: PadControlID) -> Self {
            Self(x: control.spec.x, y: control.spec.y, scale: 1, shown: true)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case placements
        case opacity
        case hidden
    }

    /// Every control's placement.
    public private(set) var placements: [PadControlID: Placement]
    /// How opaque the controls are, one of `PadLayout.opacities`.
    public var opacity: Double
    /// The player hid every control from the toolbar.
    public var hidden: Bool

    /// The opacities the toolbar's fade button steps through.
    public static let opacities = [0.35, 0.55, 0.8, 1.0]
    /// The sizes a control can be pinched to.
    public static let scales = 0.6...1.8
    /// The step of the editor's smaller and bigger buttons.
    public static let scaleStep = 0.1

    /// Every control where it starts, at the default opacity.
    public static let `default` = Self(
        placements: Dictionary(uniqueKeysWithValues: PadControlID.allCases.map { ($0, Placement.initial(for: $0)) }),
        opacity: 0.8,
        hidden: false
    )

    private init(placements: [PadControlID: Placement], opacity: Double, hidden: Bool) {
        self.placements = placements
        self.opacity = opacity
        self.hidden = hidden
    }

    /// Reads a saved layout; controls it doesn't know (from an older FactoriOS) start where they start.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let saved = try container.decode([String: Placement].self, forKey: .placements)
        var merged = Self.default.placements
        for (key, placement) in saved {
            if let control = PadControlID(rawValue: key) {
                merged[control] = Self.clamped(placement)
            }
        }
        placements = merged
        opacity = try container.decode(Double.self, forKey: .opacity)
        hidden = try container.decode(Bool.self, forKey: .hidden)
    }

    /// Writes the layout, keyed by the controls' raw values.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let byKey = Dictionary(uniqueKeysWithValues: placements.map { ($0.key.rawValue, $0.value) })
        try container.encode(byKey, forKey: .placements)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(hidden, forKey: .hidden)
    }

    /// The layout saved in `file`, or the default when there is none or it can't be read.
    public static func load(from file: URL) -> Self {
        guard let data = try? Data(contentsOf: file), let layout = try? JSONDecoder().decode(Self.self, from: data)
        else {
            // Nothing saved yet, or a file from a format FactoriOS no longer reads: the default layout.
            return .default
        }
        return layout
    }

    /// Saves the layout to `file`, replacing it in one step.
    public func save(to file: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: file, options: .atomic)
    }

    /// Where `control` is.
    public func placement(of control: PadControlID) -> Placement {
        placements[control] ?? .initial(for: control)
    }

    /// The controls on screen, in draw order.
    public var shownControls: [PadControlID] {
        PadControlID.allCases.filter { placement(of: $0).shown }
    }

    /// The controls the player removed, which the editor offers to add back.
    public var removedControls: [PadControlID] {
        PadControlID.allCases.filter { !placement(of: $0).shown }
    }

    /// Moves `control`'s middle to (`x`, `y`) in the layout frame's fractions.
    public mutating func move(_ control: PadControlID, x: Double, y: Double) {
        var placement = placement(of: control)
        placement.x = x
        placement.y = y
        placements[control] = placement
    }

    /// Sizes `control`, kept within `PadLayout.scales`.
    public mutating func setScale(_ scale: Double, of control: PadControlID) {
        var placement = placement(of: control)
        placement.scale = min(max(scale, Self.scales.lowerBound), Self.scales.upperBound)
        placements[control] = placement
    }

    /// Takes `control` off the screen.
    public mutating func remove(_ control: PadControlID) {
        var placement = placement(of: control)
        placement.shown = false
        placements[control] = placement
    }

    /// Puts `control` back where it started.
    public mutating func add(_ control: PadControlID) {
        placements[control] = .initial(for: control)
    }

    /// Steps to the next opacity, from the most opaque back to the faintest.
    public mutating func nextOpacity() {
        let current = Self.opacities.firstIndex { $0 >= opacity - 0.01 } ?? 0
        opacity = Self.opacities[(current + 1) % Self.opacities.count]
    }

    /// Every control shown where it started, at the default opacity.
    public mutating func reset() {
        self = .default
    }

    /// A saved scale out of range (an edited file) comes back into it.
    private static func clamped(_ placement: Placement) -> Placement {
        var placement = placement
        placement.scale = min(max(placement.scale, scales.lowerBound), scales.upperBound)
        return placement
    }
}
