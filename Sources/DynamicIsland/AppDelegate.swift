import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = NotchViewModel()
    let clipboard = ClipboardManager()
    let shelf = ShelfManager()
    let music = MusicManager()
    let network = NetworkMonitor()
    let stats = SystemStats()
    let timers = TimerCenter()
    let habits = HabitStore()
    let notes = NotesStore()
    let shortcuts = AppShortcutsStore()
    let calendar = CalendarManager()
    let camera = CameraManager()
    let browser = BrowserModel()

    private var windowController: NotchWindowController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var globalClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            SettingsKeys.hoverToExpand: true,
            SettingsKeys.clearShelfOnQuit: false,
        ])
        viewModel.refreshGeometry()
        let root = NotchRootView()
            .environmentObject(viewModel)
            .environmentObject(clipboard)
            .environmentObject(shelf)
            .environmentObject(music)
            .environmentObject(network)
            .environmentObject(stats)
            .environmentObject(timers)
            .environmentObject(habits)
            .environmentObject(notes)
            .environmentObject(shortcuts)
            .environmentObject(calendar)
            .environmentObject(camera)
            .environmentObject(browser)
        windowController = NotchWindowController(viewModel: viewModel, rootView: root)
        setupStatusItem()
        setupGlobalClickMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if UserDefaults.standard.bool(forKey: SettingsKeys.clearShelfOnQuit) {
            shelf.removeAll()
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "sparkles.rectangle.stack",
                accessibilityDescription: "Dynamic Island"
            )
        }
        let menu = NSMenu()
        let open = NSMenuItem(title: "Island'ı Aç", action: #selector(expandIsland), keyEquivalent: "o")
        open.target = self
        let settings = NSMenuItem(title: "Ayarlar…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        let quit = NSMenuItem(title: "Çıkış", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(open)
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func expandIsland() {
        viewModel.expand(tab: .home)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Dynamic Island Ayarları"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: SettingsView()
                    .environmentObject(viewModel)
                    .environmentObject(shelf)
                    .environmentObject(clipboard)
            )
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Collapse when clicking outside

    private func setupGlobalClickMonitor() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.viewModel.isExpanded else { return }
                // Global monitor only fires for clicks outside our own windows.
                self.viewModel.collapseNow()
            }
        }
    }
}

enum SettingsKeys {
    static let hoverToExpand = "settings.hoverToExpand"
    static let clearShelfOnQuit = "settings.clearShelfOnQuit"
}
