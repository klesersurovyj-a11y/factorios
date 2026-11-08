import FactoriOSCore
import Foundation
import SwiftUI
import UIKit

/// FactoriOS's and Factorio's logs, refreshed every two seconds, to read or copy into a problem report.
struct LogsView: View {
    let paths: GamePaths
    let settings: GameSettings

    @State private var text = ""
    @State private var copied = false

    var body: some View {
        ScrollViewReader { reader in
            ScrollView([.vertical, .horizontal]) {
                Text(text.isEmpty ? "Reading the logs…" : text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .id(Self.bottom)
            }
            .onChange(of: text) {
                reader.scrollTo(Self.bottom, anchor: .bottom)
            }
        }
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(copied ? "Copied" : "Copy all", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = text
                    copied = true
                }
                .disabled(text.isEmpty)
            }
        }
        .task {
            let device = Self.deviceSummary(settings: settings)
            let logPaths = paths
            while !Task.isCancelled {
                // Off the main thread: Factorio's log can be long.
                let logs = await Task.detached(priority: .utility) { LogReader.read(paths: logPaths) }.value
                text = device + logs
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .task(id: copied) {
            guard copied else {
                // Nothing was copied: no label to put back.
                return
            }
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private static let bottom = "bottom"

    /// What a problem report needs besides the logs: the device, the system, FactoriOS and the settings.
    @MainActor
    private static func deviceSummary(settings: GameSettings) -> String {
        let device = UIDevice.current
        let app = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let onOff = { (on: Bool) in on ? "on" : "off" }
        let chosen = [
            "\(settings.frameRate.rawValue) FPS",
            "frame \(settings.frame)",
            "UI \(settings.uiScale)",
            "sprites \(settings.spriteQuality.rawValue)",
            "graphics \(settings.lightGraphics ? "light" : "full")",
            "FPS counter \(onOff(settings.fpsCounter))",
            "detailed logs \(onOff(settings.detailedLogs))",
        ]
        return """
            ── device ──
            \(device.model) · \(device.systemName) \(device.systemVersion) · FactoriOS \(app)
            Settings: \(chosen.joined(separator: " · "))

            """
    }
}

/// Reads the ends of the logs, off the main thread: Factorio's log can be long.
enum LogReader {
    /// Factorio's first lines say what it runs on; a log full of errors can push them out of its last lines.
    private static let gameLogHead = 60
    private static let gameLogTail = 340
    private static let otherLogTail = 200

    /// FactoriOS's logs and Factorio's current one, each under its name.
    static func read(paths: GamePaths) -> String {
        var sections: [String] = []
        let manager = FileManager.default
        let own = (try? manager.contentsOfDirectory(at: paths.logs, includingPropertiesForKeys: nil)) ?? []
        for file in own.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            sections.append(section(file, head: 0, tail: otherLogTail))
        }
        sections.append(section(paths.gameLog, head: gameLogHead, tail: gameLogTail))
        return sections.joined(separator: "\n")
    }

    /// A log's `head` first lines and `tail` last lines, with a note of how many were left out between them.
    private static func section(_ file: URL, head: Int, tail: Int) -> String {
        let title = "── \(file.lastPathComponent) ──\n"
        guard let data = try? Data(contentsOf: file) else {
            return title + "(none yet)\n"
        }
        guard !data.isEmpty else {
            return title + "(empty)\n"
        }
        // Latin-1 decodes any bytes, for a log cut mid-character.
        let decoded = String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1) ?? ""
        let lines = decoded.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let between = lines.count - head - tail
        guard between > 0 else {
            return title + lines.joined(separator: "\n") + "\n"
        }
        let kept = lines.prefix(head) + ["… \(between) lines …"] + lines.suffix(tail)
        return title + kept.joined(separator: "\n") + "\n"
    }
}
