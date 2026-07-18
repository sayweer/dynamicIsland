import AppKit
import Combine
import UniformTypeIdentifiers

struct AppShortcut: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var path: String
}

/// One-click launchers for the user's favorite apps.
@MainActor
final class AppShortcutsStore: ObservableObject {
    @Published var shortcuts: [AppShortcut] = [] { didSet { persist() } }

    /// Dosyası şu an erişilemeyen (ör. bağlı olmayan harici/ağ birimi) kısayollar:
    /// görünümden gizlenir ama her persist'te diske geri yazılır — böylece birim
    /// yeniden bağlanınca sonraki açılışta geri gelirler, kalıcı silinmezler.
    private var offlineShortcuts: [AppShortcut] = []
    private var loading = true

    init() {
        let saved = Persistence.load([AppShortcut].self, from: "shortcuts.json") ?? []
        offlineShortcuts = saved.filter { !FileManager.default.fileExists(atPath: $0.path) }
        shortcuts = saved.filter { FileManager.default.fileExists(atPath: $0.path) }
        loading = false
    }

    func icon(for shortcut: AppShortcut) -> NSImage {
        NSWorkspace.shared.icon(forFile: shortcut.path)
    }

    func launch(_ shortcut: AppShortcut) {
        let url = URL(fileURLWithPath: shortcut.path)
        NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
    }

    func addViaOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Uygulama Seç"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            add(url: url)
        }
    }

    func add(url: URL) {
        let path = url.path
        guard !shortcuts.contains(where: { $0.path == path }),
              !offlineShortcuts.contains(where: { $0.path == path }) else { return }
        let name = url.deletingPathExtension().lastPathComponent
        shortcuts.append(AppShortcut(id: UUID(), name: name, path: path))
    }

    func remove(_ shortcut: AppShortcut) {
        shortcuts.removeAll { $0.id == shortcut.id }
    }

    private func persist() {
        guard !loading else { return }
        Persistence.save(shortcuts + offlineShortcuts, to: "shortcuts.json")
    }
}
