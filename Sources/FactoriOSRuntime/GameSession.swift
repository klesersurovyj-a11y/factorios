import Darwin
import FactoriOSCompat
import FactoriOSCore
import Foundation
import GameController
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
    ]

    private let paths: GamePaths
    private let launcherWindow: UIWindow
    private let makeOverlay: @MainActor (any GameInput, GameSettings) -> UIViewController
    private var overlayWindow: UIWindow?
    private var gameWindow: UIWindow?
    private var input: SDLGameInput?
    private var margin: CGFloat = 0
    private var observers: [any NSObjectProtocol] = []

    init(
        paths: GamePaths,
        launcherWindow: UIWindow,
        overlay: @escaping @MainActor (any GameInput, GameSettings) -> UIViewController
    ) {
        self.paths = paths
        self.launcherWindow = launcherWindow
        self.makeOverlay = overlay
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
        overlayWindow = RuntimeWindows.makeOverlayWindow(root: makeOverlay(gameInput, settings))
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
        let store = SettingsStore(file: paths.settingsFile)
        let keyboardAndMouse = GCKeyboard.coalesced != nil && GCMouse.current != nil
        let settings = try FactorioConfig.write(
            paths: paths,
            settings: store.load(),
            keyboardAndMouse: keyboardAndMouse
        )
        try store.save(settings)
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
        FOSSDLSetMainReady()
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
            ) { [weak self] notification in
                let window = notification.object as? UIWindow
                MainActor.assumeIsolated {
                    self?.adoptGameWindow(candidate: window)
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

    /// Adopts SDL's game window once.
    ///
    /// SDL's UIKit backend creates a plain `UIWindow`, so the class can't identify it. SDL itself is asked first:
    /// the UIWindow in the game's first SDL window's SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER property. Only when SDL
    /// has a window but doesn't expose that property is the notifying visible window taken, provided it is neither
    /// the launcher nor the overlay window FactoriOS created.
    private func adoptGameWindow(candidate: UIWindow?) {
        guard gameWindow == nil, let window = FOSSDLGameWindow() ?? fallbackGameWindow(candidate) else {
            // Already adopted, or SDL hasn't created the game's window yet; a later notification brings it.
            return
        }
        gameWindow = window
        var frame = window.frame
        if margin > 0 {
            let screen = window.windowScene?.screen.bounds ?? RuntimeWindows.screenBounds
            frame = screen.insetBy(dx: margin, dy: margin)
            // The margin shows what is behind the game's window: nothing, which is black.
            window.backgroundColor = .black
            FOSCompatSetWindowFrame(window, frame)
        }
        input?.gameWindowFrame = frame
    }

    /// The notifying window as SDL's, for an SDL that has a window but no UIKit window property.
    private func fallbackGameWindow(_ candidate: UIWindow?) -> UIWindow? {
        guard FOSSDLHasWindow(), let candidate, !candidate.isHidden else {
            // No SDL window yet, or nothing visible to take.
            return nil
        }
        let isOurs = candidate === launcherWindow || candidate === overlayWindow
        return isOurs ? nil : candidate
    }
}
