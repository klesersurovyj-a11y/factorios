import FactoriOSCore
import GameController
import UIKit

/// The layer over the game: the on-screen controller, its toolbar and touch gestures on the game.
///
/// Its root view is transparent and takes no touches itself; the game's gestures, the pad and the toolbar are
/// subviews. Without a `GameInput` it's the layout editor Settings opens, over a plain background.
final class OverlayViewController: UIViewController {
    private let input: (any GameInput)?
    private let vibration: Bool
    private let layoutFile: URL?
    private let onFinishEditing: (() -> Void)?
    private let padView: PadView
    private let toolbar = PadToolbar()
    private let gameView: GameTouchView?
    private let hint = UILabel()
    private let tickFeedback = UISelectionFeedbackGenerator()
    private let clickFeedback = UIImpactFeedbackGenerator(style: .light)
    private var keyboardShown = false

    /// A physical controller is connected: the on-screen controls step aside.
    private var padInHand = false {
        didSet { refresh() }
    }

    /// Creates the overlay.
    ///
    /// - Parameters:
    ///   - input: The running game's input, or `nil` for the layout editor in Settings.
    ///   - settings: The player's settings: vibration turns the controls' haptics on.
    ///   - layoutFile: Where the controller layout is saved, or `nil` when there's no container to save it in.
    ///   - onFinishEditing: Called when the editor's Done closes the Settings editor.
    init(
        input: (any GameInput)?, settings: GameSettings, layoutFile: URL?, onFinishEditing: (() -> Void)?
    ) {
        self.input = input
        vibration = settings.vibration
        self.layoutFile = layoutFile
        self.onFinishEditing = onFinishEditing
        let layout = layoutFile.map { PadLayout.load(from: $0) } ?? .default
        padView = PadView(input: input, layout: layout)
        gameView = input.map { GameTouchView(input: $0) }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        // Built in code only, never from a storyboard.
        nil
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var prefersStatusBarHidden: Bool { true }

    override func loadView() {
        let root = PassthroughView()
        root.backgroundColor = input == nil ? .black : .clear
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let gameView {
            view.addSubview(gameView)
        }
        view.addSubview(padView)
        if input == nil {
            hint.text = "Drag a control to move it, pinch it to resize it. Tap one, then use the tools above."
            hint.textColor = .secondaryLabel
            hint.font = .preferredFont(forTextStyle: .footnote)
            hint.textAlignment = .center
            hint.numberOfLines = 0
            view.addSubview(hint)
            padView.isEditing = true
        }
        view.addSubview(toolbar)
        padView.alpha = padView.controller.layout.opacity
        padView.onFeedback = { [weak self] feedback in self?.playHaptic(feedback) }
        toolbar.onTool = { [weak self] tool in self?.use(tool) }
        toolbar.onAdd = { [weak self] control in self?.add(control) }
        observeControllers()
        controllersChanged()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gameView?.frame = view.bounds
        padView.frame = view.bounds
        toolbar.frame = view.bounds
        hint.frame = view.bounds.insetBy(dx: 40, dy: 0).divided(atDistance: 60, from: .maxYEdge).slice
        refresh()
    }

    /// Redraws the controls and puts up the tools for the current state.
    private func refresh() {
        guard isViewLoaded else {
            // Nothing on screen yet; viewDidLoad shows the first state.
            return
        }
        padView.stepsAside = padInHand && !padView.isEditing
        let tools: [PadTool]
        if padView.isEditing {
            tools = PadTool.editing
        } else if padInHand {
            tools = PadTool.padInHand
        } else if padView.controller.layout.hidden {
            tools = PadTool.hidden
        } else {
            tools = PadTool.playing
        }
        // From the view itself: the pad view measures itself only after this layout pass.
        let geometry = PadGeometry(width: view.bounds.width, height: view.bounds.height)
        toolbar.show(
            tools,
            removed: padView.controller.layout.removedControls,
            size: geometry.toolSize,
            top: geometry.toolbarTop
        )
    }

    private func use(_ tool: PadTool) {
        playHaptic(.click)
        switch tool {
        case .edit:
            padView.controller.layout.hidden = false
            padView.isEditing = true
        case .fade:
            padView.updateLayout { layout, _ in layout.nextOpacity() }
            saveLayout()
        case .hide, .show:
            padView.releaseAll()
            padView.updateLayout { layout, _ in layout.hidden = tool == .hide }
            saveLayout()
        case .keyboard:
            keyboardShown.toggle()
            input?.setKeyboardVisible(keyboardShown)
        case .remove:
            padView.updateLayout { layout, editor in editor.removeSelected(from: &layout) }
        case .smaller, .bigger:
            padView.updateLayout { layout, editor in editor.resizeSelected(by: tool == .bigger ? 1 : -1, in: &layout) }
        case .reset:
            padView.updateLayout { layout, editor in
                layout.reset()
                editor.select(nil)
            }
        case .done:
            padView.isEditing = false
            saveLayout()
            onFinishEditing?()
        case .add:
            // The add tool opens its menu of removed controls; picking one calls add(_:).
            break
        }
        refresh()
    }

    private func add(_ control: PadControlID) {
        playHaptic(.click)
        padView.updateLayout { layout, editor in
            layout.add(control)
            editor.select(control)
        }
        refresh()
    }

    private func saveLayout() {
        guard let layoutFile else {
            // No container to save in: the layout lasts as long as the overlay.
            return
        }
        do {
            try padView.controller.layout.save(to: layoutFile)
        } catch {
            // Goes to stderr, which FactoriOS keeps in its logs.
            NSLog("FactoriOS: couldn't save the controller layout: %@", error.localizedDescription)
        }
    }

    private func playHaptic(_ feedback: PadFeedback) {
        guard vibration else {
            // The player turned vibration off.
            return
        }
        switch feedback {
        case .silent:
            break
        case .tick:
            tickFeedback.selectionChanged()
        case .click:
            clickFeedback.impactOccurred()
        }
    }

    /// The controls step aside while a physical controller is connected, and come back when it's gone; the
    /// fingers let go of everything when the app leaves the screen.
    private func observeControllers() {
        // Selector observers go away with the overlay by themselves.
        let center = NotificationCenter.default
        let changed = #selector(controllersChanged)
        center.addObserver(self, selector: changed, name: .GCControllerDidConnect, object: nil)
        center.addObserver(self, selector: changed, name: .GCControllerDidDisconnect, object: nil)
        let resign = #selector(appWillResignActive)
        center.addObserver(self, selector: resign, name: UIApplication.willResignActiveNotification, object: nil)
    }

    @objc
    private func controllersChanged() {
        padInHand = GCController.controllers().contains { $0.extendedGamepad != nil }
    }

    @objc
    private func appWillResignActive() {
        padView.releaseAll()
        gameView?.cancel()
    }
}
