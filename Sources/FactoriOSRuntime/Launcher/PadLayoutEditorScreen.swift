import SwiftUI
import UIKit

/// The controller layout editor from Settings: the in-game overlay, editing, over a plain background.
struct PadLayoutEditorScreen: UIViewControllerRepresentable {
    let settings: GameSettings
    let layoutFile: URL
    /// Called when the player taps Done; the layout is saved by then.
    let onDone: () -> Void

    func makeUIViewController(context _: Context) -> OverlayViewController {
        OverlayViewController(input: nil, settings: settings, layoutFile: layoutFile, onFinishEditing: onDone)
    }

    func updateUIViewController(_: OverlayViewController, context _: Context) {
        // The editor keeps its own state until Done; nothing from SwiftUI changes it meanwhile.
    }
}
