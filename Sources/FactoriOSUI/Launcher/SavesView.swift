import FactoriOSCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// The player's saves: the list, Import from anywhere Files reaches, and Export of them all to a folder.
struct SavesView: View {
    let model: LauncherModel

    @State private var importing = false
    @State private var exporting = false
    @State private var exportDocument: SavesFolderDocument?
    @State private var status: String?

    var body: some View {
        List {
            if let status {
                Section {
                    Text(status)
                }
            }
            if let error = model.savesError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            Section {
                if model.saves.isEmpty {
                    Text("No saves yet. Factorio's saves appear here, and in the Factorio folder in Files.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.saves) { save in
                    HStack {
                        Label(save.name, systemImage: "doc.zipper")
                        Spacer()
                        Text(save.modified, format: .dateTime.day().month().year().hour().minute())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(countText)
            }
        }
        .navigationTitle("Saves")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Import", systemImage: "square.and.arrow.down") { importing = true }
                Button("Export", systemImage: "square.and.arrow.up") { export() }
                    .disabled(model.saves.isEmpty)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                status = model.importSaves(urls)
            case .failure(let error):
                status = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $exporting,
            document: exportDocument,
            contentType: .folder,
            defaultFilename: "Factorio saves"
        ) { result in
            switch result {
            case .success:
                status = model.saves.count == 1 ? "Exported 1 save." : "Exported \(model.saves.count) saves."
            case .failure(let error):
                status = error.localizedDescription
            }
        }
        .onAppear { model.refreshSaves() }
    }

    private var countText: String {
        switch model.saves.count {
        case 0:
            "Saves"
        case 1:
            "1 save"
        default:
            "\(model.saves.count) saves"
        }
    }

    private func export() {
        do {
            exportDocument = SavesFolderDocument(folder: try model.exportFolder())
            exporting = true
        } catch {
            status = "Couldn't gather the saves: \(error.localizedDescription)"
        }
    }
}

/// A folder of saves, for the system's export sheet.
struct SavesFolderDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.folder]

    /// The folder `SaveLibrary.exportAll(to:)` filled.
    let folder: URL

    init(folder: URL) {
        self.folder = folder
    }

    init(configuration _: ReadConfiguration) throws {
        // Only ever exported: SwiftUI reads documents back only in DocumentGroup apps, which FactoriOS isn't.
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: folder, options: .immediate)
    }
}
