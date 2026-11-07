/// A point on the overlay, in points from its top-left corner.
public struct PadPoint: Equatable, Sendable {
    /// Across.
    public var x: Double
    /// Down.
    public var y: Double

    /// Creates a point.
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// The distance to `other`.
    public func distance(to other: Self) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}

/// Where a `PadLayout`'s controls sit on a screen of a given size.
///
/// The layout is drawn in a phone-shaped frame, at most a phone's height, so a tablet's controls are a phone's size;
/// each control is measured from its anchor's corner of the screen, and kept on screen.
public struct PadGeometry: Equatable, Sendable {
    /// The phone the layout was made on, sideways: 2.2 times as wide as high.
    private static let frameAspect = 2.2
    /// About a phone's height sideways, in points.
    private static let maxFrame = 480.0
    /// A pill's touch area across, in radii out from its middle.
    private static let pillReachX = 2.2
    /// A pill's touch area down, in radii out from its middle.
    private static let pillReachY = 1.25
    /// The toolbar's buttons' side, as a fraction of the frame's height.
    private static let toolFraction = 0.085
    /// The toolbar's distance from the top, as a fraction of the frame's height.
    private static let toolbarTopFraction = 0.025

    /// The overlay's width.
    public let width: Double
    /// The overlay's height.
    public let height: Double
    /// The height of the frame the layout is drawn in; sizes are fractions of it.
    public let frame: Double

    private var frameWidth: Double { frame * Self.frameAspect }

    /// Fits the layout frame on an overlay `width` by `height` points.
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
        frame = max(0, min(height, width / Self.frameAspect, Self.maxFrame))
    }

    /// The side of a toolbar button.
    public var toolSize: Double { frame * Self.toolFraction }
    /// The toolbar's distance from the top.
    public var toolbarTop: Double { frame * Self.toolbarTopFraction }

    /// The radius of `control` (half a pill's height).
    public func radius(of control: PadControlID, in layout: PadLayout) -> Double {
        control.size * layout.placement(of: control).scale * frame / 2
    }

    /// Half of `control`'s width: a pill is twice as wide as high.
    public func halfWidth(of control: PadControlID, in layout: PadLayout) -> Double {
        let radius = radius(of: control, in: layout)
        return control.isPill ? 2 * radius : radius
    }

    /// The middle of `control`, kept on screen: a layout made on a bigger screen may reach past this one.
    public func center(of control: PadControlID, in layout: PadLayout) -> PadPoint {
        let placement = layout.placement(of: control)
        let x = frameLeft(of: control) + placement.x * frameWidth
        let y = frameTop(of: control) + placement.y * frame
        return PadPoint(
            x: Self.onScreen(x, half: halfWidth(of: control, in: layout), size: width),
            y: Self.onScreen(y, half: radius(of: control, in: layout), size: height)
        )
    }

    /// The topmost shown control under `point`, if any.
    public func control(at point: PadPoint, in layout: PadLayout) -> PadControlID? {
        guard !layout.hidden else {
            // Hidden controls take no touches.
            return nil
        }
        for control in layout.shownControls.reversed() {
            let radius = radius(of: control, in: layout)
            let middle = center(of: control, in: layout)
            let hit: Bool
            if control.isPill {
                hit =
                    abs(point.x - middle.x) <= Self.pillReachX * radius
                    && abs(point.y - middle.y) <= Self.pillReachY * radius
            } else {
                hit = point.distance(to: middle) <= radius * control.kind.reach
            }
            if hit {
                return control
            }
        }
        return nil
    }

    /// Puts `control`'s middle at `point`, kept on screen: the inverse of `center(of:in:)`.
    public func move(_ control: PadControlID, to point: PadPoint, in layout: inout PadLayout) {
        guard frame > 0 else {
            // Nothing to measure on a zero-sized overlay.
            return
        }
        let x = Self.onScreen(point.x, half: halfWidth(of: control, in: layout), size: width)
        let y = Self.onScreen(point.y, half: radius(of: control, in: layout), size: height)
        layout.move(control, x: (x - frameLeft(of: control)) / frameWidth, y: (y - frameTop(of: control)) / frame)
    }

    private func frameLeft(of control: PadControlID) -> Double {
        (width - frameWidth) * control.anchor.across
    }

    private func frameTop(of control: PadControlID) -> Double {
        (height - frame) * control.anchor.down
    }

    private static func onScreen(_ position: Double, half: Double, size: Double) -> Double {
        min(max(position, min(half, size / 2)), max(size - half, size / 2))
    }
}
