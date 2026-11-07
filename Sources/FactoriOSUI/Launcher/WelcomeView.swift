import FactoriOSCore
import FactoriOSRuntime
import Foundation
import SwiftUI

/// Before the game is in: what FactoriOS needs and where to get it, in two steps.
struct WelcomeView: View {
    let installation: GameInstallation
    /// Why the last import failed, if it did.
    let error: String?

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("FactoriOS")
                        .font(.largeTitle.bold())
                    Text("Your own Factorio, running on this device.")
                        .font(.title3)
                    Text(
                        """
                        FactoriOS runs the macOS version of Factorio you bought. It includes none of the game: \
                        you import it from the disk image on factorio.com.
                        """
                    )
                    .foregroundStyle(.secondary)
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 16) {
                    certificateStep
                    gameStep
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(32)
        }
    }

    private var certificateStep: some View {
        StepCard(number: 1, title: "Apple Development identity", done: installation.hasSigningIdentity) {
            Text(
                """
                iOS only runs code signed for this device. Export the Apple Development identity used to install \
                FactoriOS from macOS Keychain as a .p12, then pick it here. FactoriOS signs the game with that same \
                identity.
                """
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            CertificateImportButton(
                installation: installation,
                title: installation.hasSigningIdentity ? "Replace identity" : "Import identity"
            )
        }
    }

    private var gameStep: some View {
        StepCard(number: 2, title: "Factorio", done: false) {
            Text(
                """
                Download the macOS disk image (.dmg) from factorio.com/download, save it to Files, then import it. \
                The demo works too.
                """
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            GameImportButton(installation: installation, title: "Import Factorio")
                .buttonStyle(.borderedProminent)
            if !installation.hasSigningIdentity {
                Text("Import the certificate first.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One numbered step of the welcome screen.
private struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    let done: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title).font(.headline)
            } icon: {
                Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                    .foregroundStyle(done ? Color.green : Color.orange)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The game's import, conversion and signing, with how far it got.
struct InstallProgressView: View {
    /// What the installation is doing.
    enum Step {
        /// Copying the game out of the disk image.
        case importing(ExtractionProgress)
        /// Turning the macOS program into an iOS library.
        case converting
        /// Signing it with the player's certificate.
        case signing
    }

    let step: Step

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.title2.bold())
            switch step {
            case .importing(let progress):
                ProgressView(value: fraction(progress))
                    .frame(maxWidth: 420)
                Text(progress.path)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 420)
                Text(byteSummary(progress))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .converting, .signing:
                ProgressView()
            }
            Text("Keep FactoriOS open until it's done.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        switch step {
        case .importing:
            "Importing Factorio"
        case .converting:
            "Converting the game for iOS"
        case .signing:
            "Signing with your certificate"
        }
    }

    private func fraction(_ progress: ExtractionProgress) -> Double {
        guard progress.bytesTotal > 0 else {
            return 0
        }
        return min(1, Double(progress.bytesDone) / Double(progress.bytesTotal))
    }

    private func byteSummary(_ progress: ExtractionProgress) -> String {
        let done = ByteCountFormatter.string(fromByteCount: Int64(progress.bytesDone), countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: Int64(progress.bytesTotal), countStyle: .file)
        return "\(done) of \(total)"
    }
}
