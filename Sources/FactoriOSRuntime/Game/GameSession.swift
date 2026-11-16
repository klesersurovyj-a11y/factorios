import Darwin
import FactoriOSCompat
import FactoriOSCore
import Foundation
import GameController
import Metal
import UIKit

/// One run of the game.
///
/// Prepares the configuration, environment and compatibility layer, loads the game, shows the overlay above it and
/// calls its entry point. The game's static state can't be set up twice, so once the game is
/// loaded the session ends with the process.
@MainActor
final class GameSession {
    /// SDL hints set before the game starts SDL.
    private static let hints = [
        // Dimmed home indicator; a swipe brings it back, then a second swipe goes home.
        "SDL_IOS_HIDE_HOME_INDICATOR": "2",
        // The overlay turns touches into the game's input; raw SDL touches must not move the mouse as well.
        "SDL_TOUCH_MOUSE_EVENTS": "0",
        // The accelerometer would show up as a second joystick.
        "SDL_ACCELEROMETER_AS_JOYSTICK": "0",
        // The on-screen pad is the overlay's, not a focused window's: without this, SDL drops presses and stick moves
        // away from the first value it saw whenever its window isn't key, so a stick stays stuck off centre.
        "SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS": "1",
    ]

    private let paths: GamePaths
    private let launcherWindow: UIWindow
    private var overlayWindow: UIWindow?
    private var gameWindow: UIWindow?
    private var input: SDLGameInput?
    private var margin: CGFloat = 0
    private var observers: [any NSObjectProtocol] = []
    private var geometryObservation: NSKeyValueObservation?

    init(paths: GamePaths, launcherWindow: UIWindow) {
        self.paths = paths
        self.launcherWindow = launcherWindow
    }

    /// Starts the game for `request` and exits the process with its status.
    ///
    /// Throws, leaving the launcher up, when the game can't be loaded.
    func run(_ request: LaunchRequest) throws -> Never {
        guard let library = paths.bundledLibrary, let manifestFile = paths.bundledSlotManifest else {
            throw GameLaunchError.notInstalled
        }
        let settings = try prepareSettings()
        let manifest = try GameLoader.readManifest(manifestFile)
        configureEnvironment(settings)
        configureSDL(settings)
        configureCompat(settings)
        let gameInput = try SDLGameInput(haptics: settings.vibration ? RumbleHaptics() : nil)
        try redirectOutput()
        let game = try GameLoader.load(library: library, manifest: manifest)

        // The game is loaded: from here on it owns the process.
        input = gameInput
        margin = CGFloat(settings.frame.rawValue)
        launcherWindow.isHidden = true
        launcherWindow.rootViewController = nil
        let overlay = OverlayViewController(
            input: gameInput, settings: settings, layoutFile: paths.padLayoutFile, onFinishEditing: nil
        )
        overlayWindow = RuntimeWindows.makeOverlayWindow(root: overlay)
        observeWindows()
        observeLifecycle()
        let arguments = arguments(for: request)
        RuntimeLog.write("Starting Factorio: \(arguments.joined(separator: " "))", paths: paths)
        let status = game.callEntry(arguments: arguments, executablePath: paths.gameExecutable.path)
        RuntimeLog.write("Factorio exited with status \(status)", paths: paths)
        fflush(nil)
        exit(status)
    }

    /// Writes config.ini from the settings and saves what that changed (whether light graphics are applied).
    private func prepareSettings() throws -> GameSettings {
        let screen = RuntimeWindows.windowScene.screen.nativeBounds
        let device = FactorioConfig.Device(
            keyboardAndMouse: GCKeyboard.coalesced != nil && GCMouse.current != nil,
            supportsBCTextures: MTLCreateSystemDefaultDevice()?.supportsBCTextureCompression ?? false,
            screenHeight: Int(min(screen.width, screen.height))
        )
        let saved = GameSettings.load(from: paths.settingsFile)
        let settings = try FactorioConfig.write(paths: paths, settings: saved, device: device)
        try settings.save(to: paths.settingsFile)
        return settings
    }

    private func configureEnvironment(_ settings: GameSettings) {
        // The game's static SDL3 forwards every call to the SDL3 FactoriOS bundles.
        setenv("SDL3_DYNAMIC_API", AppEntry.sdlLibrary.path, 1)
        // The container: Factorio finds nothing of its own there; config.ini points it at its data.
        setenv("HOME", NSHomeDirectory(), 1)
        // Detailed logs: Metal's validation layer, which also has to be on before the game's device exists.
        if settings.detailedLogs {
            setenv("MTL_DEBUG_LAYER", "1", 1)
        } else {
            unsetenv("MTL_DEBUG_LAYER")
        }
    }

    private func configureSDL(_ settings: GameSettings) {
        var hints = Self.hints
        if settings.detailedLogs {
            hints["SDL_LOGGING"] = "*=verbose"
        }
        for (name, value) in hints where !FOSSDLSetHint(name, value) {
            RuntimeLog.write("SDL refused hint \(name)=\(value): \(FOSSDLLastError())", paths: paths)
        }
    }

    private func configureCompat(_ settings: GameSettings) {
        FOSCompatSetExecutablePath(paths.gameExecutable.path)
        FOSCompatInstallMetalFixes()
        FOSCompatSetFrameRateCap(settings.frameRate.rawValue)
        let logPaths = paths
        FOSCompatSetRestartHandler { arguments in
    MainActor.assumeIsolated {
        RestartPrompt.show(arguments: arguments, paths: logPaths)
    }
    // RestartPrompt.show never returns, but the handler type expects Void
}
    }

    /// Sends the game's stdout and stderr to `game.log` in the logs folder.
    private func redirectOutput() throws {
        try FileManager.default.createDirectory(at: paths.logs, withIntermediateDirectories: true)
        let log = paths.logs.appendingPathComponent("game.log")
        let descriptor = open(log.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard descriptor >= 0 else {
            throw GameLaunchError.logUnavailable(code: errno)
        }
        dup2(descriptor, STDOUT_FILENO)
        dup2(descriptor, STDERR_FILENO)
        close(descriptor)
    }

    private func arguments(for request: LaunchRequest) -> [String] {
        var arguments = [paths.gameExecutable.path, "--config", paths.config.path]
        if case .continueSave(let save) = request {
            arguments += ["--load-game", save]
        }
        return arguments
    }

    /// Finds SDL's window when it appears or becomes key, to apply the Frame margin and tell the input where it is.
    private func observeWindows() {
        let names = [UIWindow.didBecomeVisibleNotification, UIWindow.didBecomeKeyNotification]
        for name in names {
            let observer = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.adoptGameWindow()
                }
            }
            observers.append(observer)
        }
    }

    /// Holds the game's frames while the app is in the background, where iOS forbids GPU work.
    private func observeLifecycle() {
        let center = NotificationCenter.default
        let background = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            FOSCompatSetBackgrounded(true)
        }
        let foreground = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            FOSCompatSetBackgrounded(false)
        }
        observers += [background, foreground]
    }

    /// Adopts SDL's game window once, and fits it again whenever the scene turns.
    ///
    /// SDL's UIKit backend creates a plain `UIWindow`, so the class can't identify it; SDL is asked instead, for the
    /// UIWindow in the game's first SDL window's SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER property.
    private func adoptGameWindow() {
        guard gameWindow == nil, let window = FOSSDLGameWindow() else {
            // Already adopted, or SDL hasn't created the game's window yet; a later notification brings it.
            return
        }
        gameWindow = window
        fitGameWindow()
        // Turning the phone round moves the camera housing to the other side.
        geometryObservation = window.windowScene?.observe(\.effectiveGeometry) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.fitGameWindow()
            }
        }
    }

    /// Puts the game's window on the screen less the camera housing's side and the Frame margin, and tells the input.
    private func fitGameWindow() {
        guard let window = gameWindow else {
            // Not adopted yet.
            return
        }
        let screen = RuntimeWindows.windowScene.screen.bounds
        let housing = overlayWindow.map { SensorHousing.insets(of: $0) } ?? .zero
        let frame = screen.inset(by: housing).insetBy(dx: margin, dy: margin)
        // Round the frame is what is behind the game's window: nothing, which is black.
        window.backgroundColor = .black
        FOSCompatSetWindowFrame(window, frame)
        input?.gameWindowFrame = frame
    }
}
