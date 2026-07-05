import AppKit
import Combine

struct ClipboardItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case text, link, file, image
    }

    let id: UUID
    let date: Date
    let kind: Kind
    /// Text content, link URL string, or file path depending on `kind`.
    let value: String
    /// Stable key used for de-duplication.
    let contentKey: String

    var fileURL: URL? {
        kind == .file ? URL(fileURLWithPath: value) : nil
    }
}

/// Watches the system pasteboard and keeps the last 20 copied items.
/// Items can be re-copied back to the pasteboard at any time.
@MainActor
final class ClipboardManager: ObservableObject {
    static let maxItems = 20

    @Published private(set) var items: [ClipboardItem] = []

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let imagesDir = Persistence.directory("ClipboardImages")

    /// Pasteboard types written by password managers / transient sources we must ignore.
    private let ignoredTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("com.agilebits.onepassword"),
    ]

    init() {
        lastChangeCount = pasteboard.changeCount
        items = Persistence.load([ClipboardItem].self, from: "clipboard.json") ?? []
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let types = pasteboard.types ?? []
        guard !types.contains(where: { ignoredTypes.contains($0) }) else { return }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let first = urls.first {
            add(kind: .file, value: first.path, contentKey: "file:\(first.path)")
        } else if types.contains(.tiff) || types.contains(.png),
                  let image = NSImage(pasteboard: pasteboard) {
            addImage(image)
        } else if let string = pasteboard.string(forType: .string),
                  !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"),
               !trimmed.contains(" "), URL(string: trimmed) != nil {
                add(kind: .link, value: trimmed, contentKey: "link:\(trimmed)")
            } else {
                add(kind: .text, value: string, contentKey: "text:\(string)")
            }
        }
    }

    private func addImage(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        var hasher = Hasher()
        hasher.combine(png.count)
        hasher.combine(png.prefix(4096))
        let key = "image:\(hasher.finalize())"
        if moveExistingToFront(contentKey: key) { return }

        let url = imagesDir.appendingPathComponent("\(UUID().uuidString).png")
        try? png.write(to: url)
        insert(ClipboardItem(id: UUID(), date: Date(), kind: .image, value: url.path, contentKey: key))
    }

    private func add(kind: ClipboardItem.Kind, value: String, contentKey: String) {
        if moveExistingToFront(contentKey: contentKey) { return }
        insert(ClipboardItem(id: UUID(), date: Date(), kind: kind, value: value, contentKey: contentKey))
    }

    private func moveExistingToFront(contentKey: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.contentKey == contentKey }) else { return false }
        let item = items.remove(at: index)
        items.insert(item, at: 0)
        persist()
        return true
    }

    private func insert(_ item: ClipboardItem) {
        items.insert(item, at: 0)
        while items.count > Self.maxItems {
            let removed = items.removeLast()
            cleanupStorage(for: removed)
        }
        persist()
    }

    // MARK: - Actions

    func copyToPasteboard(_ item: ClipboardItem) {
        pasteboard.clearContents()
        switch item.kind {
        case .text, .link:
            pasteboard.setString(item.value, forType: .string)
        case .file:
            pasteboard.writeObjects([URL(fileURLWithPath: item.value) as NSURL])
        case .image:
            if let image = NSImage(contentsOfFile: item.value) {
                pasteboard.writeObjects([image])
            }
        }
        // Our own write bumps changeCount; swallow it so the item isn't re-captured,
        // but move it to the front like a fresh copy.
        lastChangeCount = pasteboard.changeCount
        _ = moveExistingToFront(contentKey: item.contentKey)
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        cleanupStorage(for: item)
        persist()
    }

    func clearAll() {
        for item in items { cleanupStorage(for: item) }
        items.removeAll()
        persist()
    }

    private func cleanupStorage(for item: ClipboardItem) {
        if item.kind == .image {
            try? FileManager.default.removeItem(atPath: item.value)
        }
    }

    private func persist() {
        Persistence.save(items, to: "clipboard.json")
    }
}
