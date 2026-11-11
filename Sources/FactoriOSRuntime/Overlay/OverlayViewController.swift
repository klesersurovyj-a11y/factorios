import FactoriOSCompat
import UIKit

/// The layer over the game: the on-screen controller, its toolbar and touch gestures on the game.
///
/// Its root view is transparent and takes no touches itself; the game's gestures, the pad and the toolbar are
/// subviews. Without a `GameInput` it's the layout editor Settings opens, over a plain background.
final class OverlayViewController: UIViewController {
    private let input: (any GameInput)?
    private let vibration: Bool
    private let showFPS: Bool
    private let layoutFile: URL
    private let onFinishEditing: (() -> Void)?
    private let padView: PadView
    private let toolbar = PadToolbar()
    private let gameView: GameTouchView?
    private let hint = UILabel()
    private let fpsLabel = UILabel()
    private let tickFeedback = UISelectionFeedbackGenerator()
    private let clickFeedback = UIImpactFeedbackGenerator(style: .light)
    private var frameLink: CADisplayLink?
    private var sampleTime: CFTimeInterval = 0
    private var sampleFrames: UInt64 = 0

    /// Creates the overlay.
    ///
    /// - Parameters:
    ///   - input: The running game's input, or `nil` for the layout editor in Settings.
    ///   - settings: The player's settings: vibration turns the controls' haptics on.
    ///   - layoutFile: Where the controller layout is saved.
    ///   - onFinishEditing: Called when the editor's Done closes the Settings editor.
    init(
        input: (any GameInput)?, settings: GameSettings, layoutFile: URL, onFinishEditing: (() -> Void)?
    ) {
        self.input = input
        vibration = settings.vibration
        showFPS = settings.fpsCounter
        self.layoutFile = layoutFile
        self.onFinishEditing = onFinishEditing
        let layout = PadLayout.load(from: layoutFile)
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
        if showFPS {
            configureFPSCounter()
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
        observeLifecycle()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The controls and tools keep off the camera housing, as the game's window does; the game's area takes the
        // whole screen, as touches there arrive in screen points.
        let area = view.bounds.inset(by: view.window.map { SensorHousing.insets(of: $0) } ?? .zero)
        gameView?.frame = view.bounds
        padView.frame = area
        toolbar.frame = area
        hint.frame = area.insetBy(dx: 40, dy: 0).divided(atDistance: 60, from: .maxYEdge).slice
        fpsLabel.frame = CGRect(
            x: view.safeAreaInsets.left + 12, y: view.safeAreaInsets.top + 8, width: 112, height: 30)
        refresh()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // Turning the phone round keeps the size but moves the camera housing to the other side.
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.view.setNeedsLayout()
        }
    }

    private func configureFPSCounter() {
        fpsLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        fpsLabel.textColor = .white
        fpsLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        fpsLabel.textAlignment = .center
        fpsLabel.layer.cornerRadius = 6
        fpsLabel.clipsToBounds = true
        fpsLabel.isUserInteractionEnabled = false
        fpsLabel.text = "— FPS"
        view.addSubview(fpsLabel)
        sampleTime = CACurrentMediaTime()
        sampleFrames = FOSCompatPresentedFrameCount()
        let link = CADisplayLink(target: self, selector: #selector(sampleFPS))
        link.add(to: .main, forMode: .common)
        frameLink = link
    }

    @objc
    private func sampleFPS(_ link: CADisplayLink) {
        let elapsed = link.timestamp - sampleTime
        guard elapsed >= 0.5 else {
            // A shorter sample flickers too much to be useful.
            return
        }
        let frames = FOSCompatPresentedFrameCount()
        let count = frames >= sampleFrames ? frames - sampleFrames : 0
        fpsLabel.text = "\(Int((Double(count) / elapsed).rounded())) FPS"
        sampleTime = link.timestamp
        sampleFrames = frames
    }

    /// Redraws the controls and puts up the tools for the current state.
    private func refresh() {
        guard isViewLoaded else {
            // Nothing on screen yet; viewDidLoad shows the first state.
            return
        }
        let tools: [PadTool]
        if padView.isEditing {
            tools = PadTool.editing
        } else if padView.controller.layout.hidden {
            tools = PadTool.hidden
        } else {
            tools = PadTool.playing
        }
        // From the frame set above: the pad view measures itself only after this layout pass.
        let geometry = PadGeometry(width: toolbar.frame.width, height: toolbar.frame.height)
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
            // From SDL's state, not a flag of our own: the game also shows and hides it as its text fields gain focus.
            if let input {
                input.setKeyboardVisible(!input.isKeyboardVisible)
            }
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

    /// The fingers let go of everything when the app leaves the screen.
    private func observeLifecycle() {
        // Selector observers go away with the overlay by themselves.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    @objc
    private func appWillResignActive() {
        padView.releaseAll()
        gameView?.cancel()
    }
}
