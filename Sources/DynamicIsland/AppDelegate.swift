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
    private var welcomeWindow: NSWindow?
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
        observeVisibility()
        showWelcomeIfNeeded()
    }

    /// Accessory app açılışta hiçbir pencere göstermez; ilk çalıştırmada kullanıcı
    /// uygulamanın varlığını fark edemeyebilir. Tek seferlik karşılama penceresi
    /// adanın yerini öğretir ve login item seçeneğini sunar.
    private func showWelcomeIfNeeded() {
        let key = "pref.hasSeenWelcome"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let controller = NSHostingController(
            rootView: WelcomeView { [weak self] in
                guard let self else { return }
                self.welcomeWindow?.close()
                // Adanın yerini bir kez göster; kısa süre sonra kendiliğinden kapanır.
                self.viewModel.expand(tab: .home)
                self.viewModel.collapse(afterDelay: 5)
            }
            .environmentObject(prefs)
        )
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = "Hoş Geldiniz"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow = window
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalClickMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        if prefs.clearShelfOnQuit {
            shelf.removeAll()
        }
    }

    private func observePreferences() {
        // Pencere geometrisi bu tercihlere bağlı. @Published willSet sırasında
        // yayın yapar; property'nin yeni değeri yazılana dek beklemek için
        // main queue'ya bir tur atlatıyoruz (yoksa applyFrame eski değeri okur).
        Publishers.Merge4(
            prefs.$showOnNotchlessScreens.dropFirst().map { _ in () },
            prefs.$islandSizeMode.dropFirst().map { _ in () },
            prefs.$customPanelWidth.dropFirst().map { _ in () },
            prefs.$customPanelHeight.dropFirst().map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.windowController?.applyFrame() }
        .store(in: &cancellables)
    }

    /// Ağ/sistem monitörlerini yalnızca ilgili gösterge görünürken çalıştırır.
    /// Kapalı panelde CPU/RAM görünmediği için stats yavaşlar, ağ hızı da yalnız
    /// gerektiğinde örneklenir — boşta CPU tüketimini azaltır.
    private func observeVisibility() {
        // Tek kaynak: iki tercihi de taze değerleriyle birlikte okur (kural bir yerde).
        Publishers.CombineLatest(viewModel.$isExpanded, prefs.$collapsedRight)
            .sink { [weak self] expanded, right in
                guard let self else { return }
                self.stats.setActive(expanded)
                self.network.setActive(expanded || right == .network)
            }
            .store(in: &cancellables)
        // Panel açıldığında müziği hemen tazele (boşta 6s poll gecikmesini atla).
        viewModel.$isExpanded
            .filter { $0 }
            .sink { [weak self] _ in self?.music.refresh() }
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
            window.delegate = self
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

extension AppDelegate: NSWindowDelegate {
    /// Ayarlar penceresi kapanınca içeriğiyle birlikte bırakılır; aksi halde
    /// gizli penceredeki canlı önizleme timer'ları sonsuza dek çalışmaya devam eder.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow { settingsWindow = nil }
        if window === welcomeWindow { welcomeWindow = nil }
    }
}

/// Eski sürümden kalan anahtar; Preferences ilk açılışta bundan taşır.
enum SettingsKeys {
    static let clearShelfOnQuit = "settings.clearShelfOnQuit"
}
