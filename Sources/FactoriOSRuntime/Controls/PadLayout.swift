import FactoriOSCore
import Foundation

/// Where the player put the on-screen controls, which ones show, and how see-through they are.
struct PadLayout: Codable, Sendable, Equatable {
    /// A control's place and size.
    struct Placement: Codable, Sendable, Equatable {
        /// Its middle across the layout frame, from 0 (left) to 1 (right).
        var x: Double
        /// Its middle down the layout frame, from 0 (top) to 1 (bottom).
        var y: Double
        /// Its size relative to the default, within `PadLayout.scales`.
        var scale: Double
        /// Whether it's on screen; removed controls can be added back in the editor.
        var shown: Bool

        /// Where `control` starts out.
        static func initial(for control: PadControlID) -> Self {
            Self(x: control.spec.x, y: control.spec.y, scale: 1, shown: true)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case placements
        case opacity
        case hidden
    }

    /// Every control's placement.
    private(set) var placements: [PadControlID: Placement]
    /// How opaque the controls are, one of `PadLayout.opacities`.
    var opacity: Double
    /// The player hid every control from the toolbar.
    var hidden: Bool

    /// The opacities the toolbar's fade button steps through.
    static let opacities = [0.35, 0.55, 0.8, 1.0]
    /// The sizes a control can be pinched to.
    static let scales = 0.6...1.8
    /// The step of the editor's smaller and bigger buttons.
    static let scaleStep = 0.1

    /// Every control where it starts, at the default opacity.
    static let `default` = Self(
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
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Keyed by raw value, so a control a newer FactoriOS saved is skipped rather than failing the whole layout.
        let saved = try container.decode([String: Placement].self, forKey: .placements)
        var layout = Self.default
        for (key, placement) in saved {
            if let control = PadControlID(rawValue: key) {
                layout.placements[control] = placement
                // A saved scale out of range (an edited file) comes back into it.
                layout.setScale(placement.scale, of: control)
            }
        }
        layout.opacity = try container.decode(Double.self, forKey: .opacity)
        layout.hidden = try container.decode(Bool.self, forKey: .hidden)
        self = layout
    }

    /// The layout saved in `file`, or the default when there is none or it can't be read.
    static func load(from file: URL) -> Self {
        readJSON(from: file) ?? .default
    }

    /// Saves the layout to `file`, replacing it in one step.
    func save(to file: URL) throws {
        try writeJSON(to: file)
    }

    /// Where `control` is.
    func placement(of control: PadControlID) -> Placement {
        placements[control] ?? .initial(for: control)
    }

    /// The controls on screen, in draw order.
    var shownControls: [PadControlID] {
        PadControlID.allCases.filter { placement(of: $0).shown }
    }

    /// The controls the player removed, which the editor offers to add back.
    var removedControls: [PadControlID] {
        PadControlID.allCases.filter { !placement(of: $0).shown }
    }

    /// Moves a control's middle to (`x`, `y`) in the layout frame's fractions.
    mutating func move(_ control: PadControlID, x: Double, y: Double) {
        var placement = placement(of: control)
        placement.x = x
        placement.y = y
        placements[control] = placement
    }

    /// Sizes `control`, kept within `PadLayout.scales`.
    mutating func setScale(_ scale: Double, of control: PadControlID) {
        var placement = placement(of: control)
        placement.scale = min(max(scale, Self.scales.lowerBound), Self.scales.upperBound)
        placements[control] = placement
    }

    /// Takes `control` off the screen.
    mutating func remove(_ control: PadControlID) {
        var placement = placement(of: control)
        placement.shown = false
        placements[control] = placement
    }

    /// Puts `control` back where it started.
    mutating func add(_ control: PadControlID) {
        placements[control] = .initial(for: control)
    }

    /// Steps to the next opacity, from the most opaque back to the faintest.
    mutating func nextOpacity() {
        let current = Self.opacities.firstIndex { $0 >= opacity - 0.01 } ?? 0
        opacity = Self.opacities[(current + 1) % Self.opacities.count]
    }

    /// Every control shown where it started, at the default opacity.
    mutating func reset() {
        self = .default
    }
}
