import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = NotchViewModel()
    let prefs = Preferences.shared
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
    private var keyMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel.refreshGeometry()
        let root = NotchRootView()
            .environmentObject(viewModel)
            .environmentObject(prefs)
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
        setupEventMonitors()
        observePreferences()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalClickMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        if prefs.clearShelfOnQuit {
            shelf.removeAll()
        }
    }

    private func observePreferences() {
        // Window geometry depends on these; reapply when they change.
        prefs.$showOnNotchlessScreens
            .dropFirst()
            .sink { [weak self] _ in self?.windowController?.applyFrame() }
            .store(in: &cancellables)
        prefs.$islandSizeMode
            .dropFirst()
            .sink { [weak self] _ in self?.windowController?.applyFrame() }
            .store(in: &cancellables)
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
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Dynamic Island"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: SettingsView()
                    .environmentObject(viewModel)
                    .environmentObject(prefs)
                    .environmentObject(shelf)
                    .environmentObject(clipboard)
            )
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Event monitors

    private func setupEventMonitors() {
        // Collapse when clicking anywhere outside our windows.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.viewModel.isExpanded else { return }
                self.viewModel.collapseNow()
            }
        }
        // ESC collapses the island.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.viewModel.isExpanded else { return event }
            self.viewModel.collapseNow()
            return nil
        }
    }
}

/// Eski sürümden kalan anahtarlar; Preferences ilk açılışta bunlardan taşır.
enum SettingsKeys {
    static let hoverToExpand = "settings.hoverToExpand"
    static let clearShelfOnQuit = "settings.clearShelfOnQuit"
}
