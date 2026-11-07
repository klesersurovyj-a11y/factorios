import FactoriOSRuntime
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Picks the Factorio `.dmg` in the Files app and installs it: extract, convert for iOS, sign.
struct GameImportButton: View {
    let installation: GameInstallation
    let title: String

    @State private var picking = false

    var body: some View {
        Button {
            picking = true
        } label: {
            Label(title, systemImage: "square.and.arrow.down")
        }
        .disabled(!installation.hasSigningIdentity)
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.diskImageTypes) { result in
            guard case .success(let url) = result else {
                // The player cancelled, or Files couldn't hand the file over: nothing to install.
                return
            }
            Task {
                // The file stays outside the app's container: hold on to it until the import has read it.
                let accessing = url.startAccessingSecurityScopedResource()
                await installation.install(from: url)
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }
    }

    /// Apple's disk image type, and `.dmg` files that a provider didn't type.
    private static var diskImageTypes: [UTType] {
        var types: [UTType] = [.diskImage]
        if let dmg = UTType(filenameExtension: "dmg"), dmg != .diskImage {
            types.append(dmg)
        }
        return types
    }
}

/// Picks the signing certificate (`.p12`) exported from SideStore or AltStore, asks for its password and imports it.
struct CertificateImportButton: View {
    let installation: GameInstallation
    let title: String

    @State private var picking = false
    @State private var picked: URL?
    @State private var asking = false
    @State private var password = ""
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                picking = true
            } label: {
                Label(title, systemImage: "checkmark.seal")
            }
            if let failure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.pkcs12]) { result in
            guard case .success(let url) = result else {
                // The player cancelled, or Files couldn't hand the file over: nothing to import.
                return
            }
            picked = url
            password = ""
            asking = true
        }
        .alert("Certificate password", isPresented: $asking) {
            SecureField("Password", text: $password)
            Button("Import") { importPicked() }
            Button("Cancel", role: .cancel) {
                picked = nil
            }
        } message: {
            Text("The password you set when exporting the certificate. Leave it empty if there was none.")
        }
    }

    private func importPicked() {
        guard let url = picked else {
            // The alert outlived its file: nothing to import.
            return
        }
        picked = nil
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            try installation.importSigningIdentity(from: url, password: password)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
        password = ""
    }
}
