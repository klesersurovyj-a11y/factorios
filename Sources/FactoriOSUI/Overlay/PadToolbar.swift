import FactoriOSCore
import UIKit

/// A button of the overlay's toolbar.
enum PadTool {
    /// Opens the layout editor.
    case edit
    /// Steps to the next opacity.
    case fade
    /// Hides every control.
    case hide
    /// Shows the controls again.
    case show
    /// Hides or shows the system keyboard while a game text field has the focus (naming a save, pasting a blueprint
    /// string); focusing one brings the keyboard up by itself.
    case keyboard
    /// Adds a removed control back: a menu of them.
    case add
    /// Removes the selected control.
    case remove
    /// Makes the selected control smaller.
    case smaller
    /// Makes the selected control bigger.
    case bigger
    /// Every control back where it started.
    case reset
    /// Leaves the editor, saving the layout.
    case done

    /// The tools while playing with the controls shown.
    static let playing: [Self] = [.edit, .fade, .hide, .keyboard]
    /// The tools while the controls are hidden.
    static let hidden: [Self] = [.show, .keyboard]
    /// The tools while a physical controller is in use: it still needs the keyboard for typing names.
    static let padInHand: [Self] = [.keyboard]
    /// The layout editor's tools.
    static let editing: [Self] = [.add, .remove, .smaller, .bigger, .fade, .reset, .done]

    /// The tool's SF Symbol.
    var symbol: String {
        switch self {
        case .edit:
            "slider.horizontal.3"
        case .fade:
            "circle.lefthalf.filled"
        case .hide:
            "eye.slash"
        case .show:
            "eye"
        case .keyboard:
            "keyboard"
        case .add:
            "plus.square"
        case .remove:
            "trash"
        case .smaller:
            "minus.magnifyingglass"
        case .bigger:
            "plus.magnifyingglass"
        case .reset:
            "arrow.counterclockwise"
        case .done:
            "checkmark"
        }
    }

    /// The tool's name for VoiceOver.
    var title: String {
        switch self {
        case .edit:
            "Edit layout"
        case .fade:
            "Opacity"
        case .hide:
            "Hide controls"
        case .show:
            "Show controls"
        case .keyboard:
            "Keyboard"
        case .add:
            "Add a control"
        case .remove:
            "Remove control"
        case .smaller:
            "Smaller"
        case .bigger:
            "Bigger"
        case .reset:
            "Reset layout"
        case .done:
            "Done"
        }
    }
}

/// The row of tools along the top middle of the screen.
final class PadToolbar: PassthroughView {
    /// The smallest a tool gets, so it stays easy to hit on a small phone.
    private static let minimumSide: CGFloat = 34

    private let stack = UIStackView()
    private let panel = UIView()
    /// The tool the player used.
    var onTool: (PadTool) -> Void = { _ in
        // Set by the overlay before the toolbar is shown.
    }
    /// A removed control the player picked from the add menu.
    var onAdd: (PadControlID) -> Void = { _ in
        // Set by the overlay before the toolbar is shown.
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        panel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        panel.layer.cornerCurve = .continuous
        panel.isUserInteractionEnabled = false
        addSubview(panel)
        stack.axis = .horizontal
        stack.spacing = 2
        addSubview(stack)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        // Built in code only, never from a storyboard.
        nil
    }

    /// Shows `tools`, `size` points square (or the minimum), with their top `top` points below the overlay's top.
    func show(_ tools: [PadTool], removed: [PadControlID], size: CGFloat, top: CGFloat) {
        let side = max(size, Self.minimumSide)
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for tool in tools {
            stack.addArrangedSubview(makeButton(tool, side: side, removed: removed))
        }
        let width = side * CGFloat(tools.count) + stack.spacing * CGFloat(max(tools.count - 1, 0))
        stack.frame = CGRect(x: (bounds.width - width) / 2, y: top, width: width, height: side)
        panel.frame = stack.frame.insetBy(dx: -4, dy: -4)
        panel.layer.cornerRadius = side * 0.3
        panel.isHidden = tools.isEmpty
    }

    private func makeButton(_ tool: PadTool, side: CGFloat, removed: [PadControlID]) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: tool.symbol)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: side * 0.42,
            weight: .semibold
        )
        configuration.baseForegroundColor = .white
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = tool.title
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: side),
            button.heightAnchor.constraint(equalToConstant: side),
        ])
        if tool == .add {
            button.menu = addMenu(removed)
            button.showsMenuAsPrimaryAction = true
            button.isEnabled = !removed.isEmpty
        } else {
            button.addAction(UIAction { [weak self] _ in self?.onTool(tool) }, for: .touchUpInside)
        }
        return button
    }

    private func addMenu(_ removed: [PadControlID]) -> UIMenu {
        let actions = removed.map { control in
            UIAction(title: control.name) { [weak self] _ in self?.onAdd(control) }
        }
        return UIMenu(title: "Add a control", children: actions)
    }
}
