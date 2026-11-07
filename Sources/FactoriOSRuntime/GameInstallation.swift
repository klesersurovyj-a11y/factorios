public import FactoriOSCore
public import Foundation
public import Observation
import os

/// The imported game and the signed library made from it: importing, converting, signing.
@MainActor
@Observable
public final class GameInstallation {
    /// Where the installation stands.
    public enum Stage: Equatable, Sendable {
        /// Nothing is installed yet.
        case notInstalled
        /// Extracting `factorio.app` from the disk image.
        case importing(ExtractionProgress)
        /// Converting the macOS executable into an iOS library.
        case converting
        /// Signing the library with the sideloading certificate.
        case signing
        /// The game is ready to start.
        case ready(ImportedGame)
        /// The last install failed, for this reason.
        case failed(String)
    }

    /// Where the installation stands.
    public private(set) var stage: Stage
    /// Whether a signing certificate was imported; installing needs one.
    public private(set) var hasSigningIdentity: Bool

    private let paths: GamePaths

    /// Reads the state of the installation in `paths`.
    public init(paths: GamePaths) {
        self.paths = paths
        if let game = GameImporter.installedGame(paths: paths), LibraryBuilder.isBuilt(paths: paths) {
            stage = .ready(game)
        } else {
            stage = .notInstalled
        }
        let password = try? SigningPasswordStore.password()
        hasSigningIdentity =
            password != nil && FileManager.default.fileExists(atPath: paths.signingIdentity.path)
    }

    /// Imports the sideloading certificate: checks the password, then keeps the file and its password.
    public func importSigningIdentity(from p12: URL, password: String) throws {
        let scoped = p12.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                p12.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: p12)
        _ = try KeychainSigningIdentity(pkcs12: data, password: password)
        try FileManager.default.createDirectory(
            at: paths.signingIdentity.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(
            to: paths.signingIdentity,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        try SigningPasswordStore.save(password)
        hasSigningIdentity = true
    }

    /// Imports the game from a Factorio macOS disk image, converts and signs it; `stage` follows along and ends in
    /// `.ready` or `.failed`.
    public func install(from dmg: URL) async {
        stage = .importing(ExtractionProgress(bytesDone: 0, bytesTotal: 0, path: ""))
        let gamePaths = paths
        do {
            // Checked first so a missing certificate doesn't surface only after minutes of extraction.
            let identity = try KeychainSigningIdentity.load(paths: gamePaths)
            // The library made from the previous game must not outlive it, or a failed install would start it.
            try LibraryBuilder.removeBuilt(paths: gamePaths)
            let reporter = ImportProgressReporter { progress in
                Task { @MainActor in self.publishImport(progress) }
            }
            let game = try await Task.detached(priority: .userInitiated) {
                let scoped = dmg.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        dmg.stopAccessingSecurityScopedResource()
                    }
                }
                return try GameImporter.importGame(from: dmg, paths: gamePaths) { reporter.report($0) }
            }
            .value
            stage = .converting
            let converted = try await Task.detached(priority: .userInitiated) {
                try LibraryBuilder.convert(paths: gamePaths)
            }
            .value
            stage = .signing
            try await Task.detached(priority: .userInitiated) {
                try LibraryBuilder.sign(converted, identity: identity, paths: gamePaths)
            }
            .value
            stage = .ready(game)
        } catch {
            RuntimeLog.write("Install failed: \(error)", paths: gamePaths)
            stage = .failed(error.localizedDescription)
        }
    }

    /// Shows import progress, unless a later step has already begun.
    private func publishImport(_ progress: ExtractionProgress) {
        if case .importing = stage {
            stage = .importing(progress)
        }
    }
}

/// Passes on extraction progress at most once per thousandth, so the main actor isn't flooded.
private final class ImportProgressReporter: Sendable {
    private let lastPermille = OSAllocatedUnfairLock(initialState: -1)
    private let publish: @Sendable (ExtractionProgress) -> Void

    init(publish: @escaping @Sendable (ExtractionProgress) -> Void) {
        self.publish = publish
    }

    func report(_ progress: ExtractionProgress) {
        let total = max(progress.bytesTotal, 1)
        let permille = Int(min(progress.bytesDone, total) * 1_000 / total)
        let isNew = lastPermille.withLock { last in
            guard permille != last else {
                return false
            }
            last = permille
            return true
        }
        if isNew {
            publish(progress)
        }
    }
}
