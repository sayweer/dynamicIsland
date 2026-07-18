import AppKit
import Combine
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let fileName: String
    /// Path of our private copy inside Application Support — survives moves of the original.
    let storedPath: String

    var storedURL: URL { URL(fileURLWithPath: storedPath) }
}

/// Temporary file shelf: drop files onto the notch to park them,
/// drag them back out (or AirDrop them) whenever needed.
@MainActor
final class ShelfManager: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    private let shelfDir = Persistence.directory("Shelf")

    init() {
        let saved = Persistence.load([ShelfItem].self, from: "shelf.json") ?? []
        // Drop entries whose backing file disappeared.
        items = saved.filter { FileManager.default.fileExists(atPath: $0.storedPath) }
        if items.count != saved.count { persist() }
    }

    // MARK: - Adding

    func add(fileURL: URL) {
        let id = UUID()
        let itemDir = shelfDir.appendingPathComponent(id.uuidString, isDirectory: true)
        let target = itemDir.appendingPathComponent(fileURL.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: fileURL, to: target)
        } catch {
            NSLog("Shelf copy failed: \(error.localizedDescription)")
            return
        }
        items.insert(
            ShelfItem(id: id, date: Date(), fileName: fileURL.lastPathComponent, storedPath: target.path),
            at: 0
        )
        persist()
    }

    func add(imageData: Data, suggestedName: String = "Görsel") {
        let id = UUID()
        let itemDir = shelfDir.appendingPathComponent(id.uuidString, isDirectory: true)
        let target = itemDir.appendingPathComponent("\(suggestedName)-\(shortStamp()).png")
        do {
            try FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
            try imageData.write(to: target)
        } catch { return }
        items.insert(
            ShelfItem(id: id, date: Date(), fileName: target.lastPathComponent, storedPath: target.path),
            at: 0
        )
        persist()
    }

    func add(text: String) {
        let id = UUID()
        let itemDir = shelfDir.appendingPathComponent(id.uuidString, isDirectory: true)
        let target = itemDir.appendingPathComponent("Not-\(shortStamp()).txt")
        do {
            try FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
            try text.write(to: target, atomically: true, encoding: .utf8)
        } catch { return }
        items.insert(
            ShelfItem(id: id, date: Date(), fileName: target.lastPathComponent, storedPath: target.path),
            at: 0
        )
        persist()
    }

    /// Entry point for drops coming from SwiftUI `onDrop` providers.
    func handle(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    // Kaynak uygulamaya göre öğe Data (bookmark) ya da NSURL gelebilir.
                    let url: URL?
                    if let direct = item as? URL {
                        url = direct
                    } else if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else {
                        url = nil
                    }
                    guard let url else { return }
                    Task { @MainActor in self.add(fileURL: url) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                handled = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data,
                          let rep = NSBitmapImageRep(data: data),
                          let png = rep.representation(using: .png, properties: [:]) else { return }
                    Task { @MainActor in self.add(imageData: png) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    var text: String?
                    if let s = item as? String { text = s }
                    else if let d = item as? Data { text = String(data: d, encoding: .utf8) }
                    guard let text, !text.isEmpty else { return }
                    Task { @MainActor in self.add(text: text) }
                }
            }
        }
        return handled
    }

    // MARK: - Actions

    func airDrop(_ item: ShelfItem) {
        airDrop(urls: [item.storedURL])
    }

    func airDropAll() {
        airDrop(urls: items.map(\.storedURL))
    }

    func airDrop(urls: [URL]) {
        guard !urls.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: urls)
    }

    func revealInFinder(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.storedURL])
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(at: item.storedURL.deletingLastPathComponent())
        persist()
    }

    func removeAll() {
        for item in items {
            try? FileManager.default.removeItem(at: item.storedURL.deletingLastPathComponent())
        }
        items.removeAll()
        persist()
    }

    func icon(for item: ShelfItem) -> NSImage {
        NSWorkspace.shared.icon(forFile: item.storedPath)
    }

    private func shortStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss"
        return formatter.string(from: Date())
    }

    private func persist() {
        Persistence.save(items, to: "shelf.json")
    }
}
