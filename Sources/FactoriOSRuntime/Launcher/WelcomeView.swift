import SwiftUI

/// Before the game is in: FactoriOS has to be prepared and installed from a Mac.
struct WelcomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("FactoriOS")
                    .font(.largeTitle.bold())
                Text("Your own Factorio, running on this device.")
                    .font(.title3)
                Text(
                    """
                    FactoriOS runs the macOS version of Factorio you bought. It includes none of the game, and iOS \
                    only loads game code that is inside the app bundle.
                    """
                )
                .foregroundStyle(.secondary)
                Text(
                    """
                    On a Mac with Xcode, download Factorio for macOS from factorio.com (the demo works too), then run \
                    `mise run deploy` in the FactoriOS repository. It imports and converts the disk image, embeds the \
                    signed game in the app, and installs the app and the game data here.
                    """
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
    }
}
