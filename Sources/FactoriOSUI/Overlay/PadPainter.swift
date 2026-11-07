import FactoriOSCore
import UIKit

/// Draws the on-screen controls in plain shapes and SF Symbols: FactoriOS ships none of the game's art.
@MainActor
enum PadPainter {
    private static let idleFill = UIColor.black.withAlphaComponent(0.55)
    private static let pressedFill = UIColor.systemOrange.withAlphaComponent(0.9)
    private static let edge = UIColor.white.withAlphaComponent(0.75)
    private static let glyph = UIColor.white.withAlphaComponent(0.95)
    private static let pressedGlyph = UIColor.black
    private static let selection = UIColor.systemYellow

    /// Draws `control` in the current graphics context.
    static func draw(
        _ control: PadControlID, state: PadControlState, center: CGPoint, radius: CGFloat, selected: Bool
    ) {
        switch control.kind {
        case .stick:
            drawStick(control, state: state, center: center, radius: radius)
        case .dpad:
            drawDpad(state: state, center: center, radius: radius)
        case .button, .trigger:
            drawButton(control, pressed: state.isPressed, center: center, radius: radius)
        }
        if selected {
            let ring = outline(of: control, center: center, radius: radius * 1.12)
            ring.lineWidth = 2.5
            ring.setLineDash([6, 4], count: 2, phase: 0)
            selection.setStroke()
            ring.stroke()
        }
    }

    /// The control's shape: a circle, or a pill twice as wide as high.
    static func outline(of control: PadControlID, center: CGPoint, radius: CGFloat) -> UIBezierPath {
        if control.isPill {
            let rect = CGRect(x: center.x - 2 * radius, y: center.y - radius, width: 4 * radius, height: 2 * radius)
            return UIBezierPath(roundedRect: rect, cornerRadius: radius)
        }
        return UIBezierPath(
            ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
        )
    }

    private static func drawButton(_ control: PadControlID, pressed: Bool, center: CGPoint, radius: CGFloat) {
        let shape = outline(of: control, center: center, radius: radius)
        (pressed ? pressedFill : idleFill).setFill()
        shape.fill()
        shape.lineWidth = 1.5
        edge.setStroke()
        shape.stroke()
        let color = pressed ? pressedGlyph : glyph
        switch control {
        case .view:
            drawSymbol("rectangle.on.rectangle", center: center, size: radius, color: color)
        case .menu:
            drawSymbol("line.3.horizontal", center: center, size: radius, color: color)
        default:
            drawLabel(control.label, center: center, size: radius * (control.isPill ? 0.8 : 0.85), color: color)
        }
    }

    private static func drawStick(_ control: PadControlID, state: PadControlState, center: CGPoint, radius: CGFloat) {
        let well = outline(of: control, center: center, radius: radius)
        idleFill.withAlphaComponent(0.35).setFill()
        well.fill()
        well.lineWidth = 1.5
        edge.withAlphaComponent(0.5).setStroke()
        well.stroke()
        var knobCenter = center
        if let origin = state.origin, let knob = state.knob {
            knobCenter = CGPoint(x: center.x + knob.x - origin.x, y: center.y + knob.y - origin.y)
        }
        let knobRadius = radius * 0.5
        let knob = UIBezierPath(
            ovalIn: CGRect(
                x: knobCenter.x - knobRadius,
                y: knobCenter.y - knobRadius,
                width: 2 * knobRadius,
                height: 2 * knobRadius
            )
        )
        (state.isPressed ? pressedFill : idleFill).setFill()
        knob.fill()
        knob.lineWidth = 1.5
        edge.setStroke()
        knob.stroke()
        drawLabel(
            control.label, center: knobCenter, size: knobRadius * 0.9, color: state.isPressed ? pressedGlyph : glyph)
    }

    private static func drawDpad(state: PadControlState, center: CGPoint, radius: CGFloat) {
        let arm = radius * 0.36
        let horizontal = CGRect(x: center.x - radius, y: center.y - arm, width: 2 * radius, height: 2 * arm)
        let vertical = CGRect(x: center.x - arm, y: center.y - radius, width: 2 * arm, height: 2 * radius)
        let cross = UIBezierPath(roundedRect: horizontal, cornerRadius: arm * 0.4)
        cross.append(UIBezierPath(roundedRect: vertical, cornerRadius: arm * 0.4))
        idleFill.setFill()
        cross.fill()
        cross.lineWidth = 1.5
        edge.setStroke()
        cross.stroke()
        let arrows: [(PadButton, CGFloat)] = [
            (.dpadUp, -.pi / 2), (.dpadRight, 0), (.dpadDown, .pi / 2), (.dpadLeft, .pi),
        ]
        for (button, angle) in arrows {
            let pressed = state.directions.contains(button)
            drawArrow(center: center, distance: radius * 0.66, angle: angle, size: arm * 0.75, pressed: pressed)
        }
    }

    private static func drawArrow(center: CGPoint, distance: CGFloat, angle: CGFloat, size: CGFloat, pressed: Bool) {
        let tip = CGPoint(
            x: center.x + cos(angle) * (distance + size * 0.6), y: center.y + sin(angle) * (distance + size * 0.6))
        let base = CGPoint(
            x: center.x + cos(angle) * (distance - size * 0.4), y: center.y + sin(angle) * (distance - size * 0.4))
        let across = CGPoint(x: -sin(angle) * size * 0.75, y: cos(angle) * size * 0.75)
        let arrow = UIBezierPath()
        arrow.move(to: tip)
        arrow.addLine(to: CGPoint(x: base.x + across.x, y: base.y + across.y))
        arrow.addLine(to: CGPoint(x: base.x - across.x, y: base.y - across.y))
        arrow.close()
        (pressed ? pressedFill : glyph).setFill()
        arrow.fill()
    }

    private static func drawLabel(_ text: String, center: CGPoint, size: CGFloat, color: UIColor) {
        guard !text.isEmpty, size > 1 else {
            // Nothing to write, or too small to read.
            return
        }
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let string = NSAttributedString(string: text, attributes: attributes)
        let bounds = string.size()
        string.draw(at: CGPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2))
    }

    private static func drawSymbol(_ name: String, center: CGPoint, size: CGFloat, color: UIColor) {
        let configuration = UIImage.SymbolConfiguration(pointSize: size * 0.8, weight: .semibold)
        guard
            let image = UIImage(systemName: name, withConfiguration: configuration)?
                .withTintColor(color, renderingMode: .alwaysOriginal)
        else {
            // Every symbol named here exists since iOS 15; a missing one leaves the button blank.
            return
        }
        let rect = CGRect(
            x: center.x - image.size.width / 2,
            y: center.y - image.size.height / 2,
            width: image.size.width,
            height: image.size.height
        )
        image.draw(in: rect)
    }
}
