import FactoriOSRuntime
import FactoriOSUI

/// The app's entry point.
///
/// On iOS, SDL has to own the application's start-up, so FactoriOS hands it over at once; SDL then calls back into
/// FactoriOS, which shows the launcher and, when the player starts, the game.
@main
enum FactoriOSMain {
    @MainActor
    static func main() {
        AppEntry.run(launcher: LauncherFactory.makeLauncher, overlay: LauncherFactory.makeOverlay)
    }
}
