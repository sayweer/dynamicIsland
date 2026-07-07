import AppKit
import SwiftUI

/// Borderless, transparent, always-on-top panel anchored to the top-center.
/// The window is ALWAYS sized for the expanded island so the hover target is a
/// stable size; hit-testing is limited to the island shape (NotchHostingView.hitTest)
/// so fully transparent pixels pass mouse events through to windows below.
/// Hover itself is detected by a global mouseMoved monitor (see NotchWindowController),
/// NOT SwiftUI `.onHover` — which delivers no events to an accessory app while another
/// app is frontmost.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // .statusBar(25) menü çubuğu öğeleriyle aynı katman; +8 (NotchDrop'un
        // değeri) durum öğeleriyle z-sırası çekişmesini önler.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 8)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Pencere her zaman büyük olduğundan, adanın DIŞINDAKİ şeffaf alanlarda mouse
/// olaylarını alttaki pencerelere geçirmek gerekir (yoksa ekranın üst şeridi —
/// menü çubuğu dahil — tıklanamaz olur). SwiftUI'nin kendi hit-test'i şeffaf
/// alanı da yakaladığından, hit-test'i AppKit seviyesinde ada dikdörtgenine
/// sınırlıyoruz: dışında nil → olay alta geçer; içinde SwiftUI çözer.
/// Yalnızca tıklama-geçişi (hit-test) için özelleşmiş hosting view: ada şeklinin
/// DIŞINDA nil döndürerek şeffaf alanların mouse'u alta geçirmesini sağlar.
/// Hover ALGILAMA burada DEĞİL — tek kaynak olarak NotchWindowController'daki
/// global/local mouseMoved monitörü kullanılır (iki kaynak flicker üretiyordu).
final class NotchHostingView: NSHostingView<AnyView> {
    /// Adanın pencere (content) koordinatındaki dikdörtgenini veren closure.
    var islandRect: (() -> CGRect)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let rect = islandRect?() else { return super.hitTest(point) }
        // point superview koordinatında gelir; ada dikdörtgeni self koordinatında.
        let local = convert(point, from: superview)
        return rect.contains(local) ? super.hitTest(point) : nil
    }
}

@MainActor
final class NotchWindowController {
    let panel = NotchPanel()
    private let viewModel: NotchViewModel
    private let hosting: NotchHostingView
    private var expandWork: DispatchWorkItem?
    /// Hover durumu — yalnızca değişimde aksiyon alınır (mouseMoved seli filtrelenir).
    private var hoverInside = false
    // İki bağımsız hover kaynağı (kuşak + askı), ikisi de updateHover'a besler:
    private nonisolated(unsafe) var globalMonitor: Any?
    private nonisolated(unsafe) var localMonitor: Any?

    init(viewModel: NotchViewModel, rootView: some View) {
        self.viewModel = viewModel
        self.hosting = NotchHostingView(rootView: AnyView(rootView))
        hosting.wantsLayer = true
        hosting.islandRect = { [weak hosting, weak viewModel] in
            guard let hosting, let vm = viewModel else { return .zero }
            let b = hosting.bounds
            let iw = vm.isExpanded ? vm.expandedSize.width : vm.collapsedPillSize.width
            let ih = vm.isExpanded ? vm.expandedSize.height : vm.collapsedPillSize.height
            // Ada, büyük pencerenin üst-ortasında hizalı. isFlipped'de üst kenar
            // y=0, değilse y=height; iki durumu da doğru ele al.
            let top = hosting.isFlipped ? 0 : (b.height - ih)
            return CGRect(x: (b.width - iw) / 2, y: top, width: iw, height: ih)
        }
        panel.contentView = hosting
        applyFrame()
        panel.orderFrontRegardless()

        // TEK hover kaynağı (NotchDrop tarzı, en dayanıklı): global + local
        // mouseMoved monitörü + ekran-koordinatında ada rect testi. Accessory
        // app'te, key olmayan panelde, başka uygulama önplandayken de çalışır
        // (gerçek fareyle kanıtlandı); izin gerektirmez.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updateHover(inside: self.hoverRect().contains(NSEvent.mouseLocation))
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            if let self {
                MainActor.assumeIsolated {
                    self.updateHover(inside: self.hoverRect().contains(NSEvent.mouseLocation))
                }
            }
            return event
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyFrame() }
        }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    // MARK: - Hover

    /// Hover tetikleme/koruma dikdörtgeni (EKRAN koordinatı, alt-sol origin —
    /// NSEvent.mouseLocation ile aynı uzay). Histerezis: KAPALIYKEN küçük tetikleme
    /// bölgesi (pill + küçük margin), AÇIKKEN ondan çok daha büyük koruma bölgesi.
    /// Böylece sınırda gezinen imleç aç/kapa titremesi (flicker) yapamaz. Üst kenar
    /// ekranın en tepesini de kapsar (maxY dışlayıcı olduğu için +6 taşma).
    private func hoverRect() -> CGRect {
        let wf = panel.frame
        let expanded = viewModel.isExpanded
        let iw = expanded ? viewModel.expandedSize.width : viewModel.collapsedPillSize.width
        let ih = expanded ? viewModel.expandedSize.height : viewModel.collapsedPillSize.height
        let mx: CGFloat = expanded ? 40 : 20   // yatay margin
        let mb: CGFloat = expanded ? 30 : 14   // alt margin
        return CGRect(
            x: wf.midX - iw / 2 - mx,
            y: wf.maxY - ih - mb,
            width: iw + 2 * mx,
            height: ih + mb + 6
        )
    }

    /// Tek giriş noktası; her iki kaynak da buraya besler. Sadece durum
    /// değişiminde aksiyon alır — mouseMoved seli aç/kapa döngüsü yaratmaz.
    private func updateHover(inside: Bool) {
        guard inside != hoverInside else { return }
        hoverInside = inside
        viewModel.isMouseInside = inside
        expandWork?.cancel()
        if inside {
            guard Preferences.shared.hoverToExpand, !viewModel.isExpanded else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.hoverInside else { return }
                self.viewModel.expand()
            }
            expandWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Preferences.shared.hoverDelay, execute: work)
        } else {
            viewModel.collapse(afterDelay: Preferences.shared.collapseDelay)
        }
    }

    /// Pencere her zaman genişlemiş boyutta ve çentiğe ortalı durur; aç/kapa
    /// yalnızca içindeki SwiftUI adasının boyutunu değiştirir, pencereyi değil.
    func applyFrame() {
        guard let screen = ScreenGeometry.targetScreen else {
            panel.orderOut(nil)
            return
        }
        if !screen.hasNotch && !Preferences.shared.showOnNotchlessScreens {
            panel.orderOut(nil)
            return
        }
        viewModel.refreshGeometry()

        let expanded = viewModel.expandedSize
        let width = max(expanded.width, viewModel.collapsedPillSize.width) + 60
        let height = expanded.height + 40
        // Fiziksel çentik ekran merkezinden yarım nokta kayık raporlanabilir
        // (auxiliary alanlar asimetrik); pencereyi çentiğe hizala.
        var frame = screen.topAnchoredRect(width: width, height: height)
        frame.origin.x = frame.origin.x.rounded()
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }
}
