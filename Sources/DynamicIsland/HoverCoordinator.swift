import AppKit

/// Ada aç/kapa kararlarını ekran koordinatındaki sabit bölgelerle veren,
/// histerezisli durum makinesi.
///
/// SwiftUI `.onHover` animasyon sırasında şekil ve pencere yeniden
/// boyutlandıkça sahte enter/exit üretir (aç-kapa titremesinin kaynağı).
/// Burada her fare olayında imlecin KONUMU, o anki duruma ait sabit
/// dikdörtgenle test edilir; kapalıyken küçük tetikleme bölgesi, açıkken
/// ondan çok daha büyük koruma bölgesi kullanıldığı için sınırda gezinen
/// imleç durumu asla hızlıca ileri-geri deviremez.
@MainActor
final class HoverCoordinator {
    private static let debug = ProcessInfo.processInfo.arguments.contains("--debug-geometry")
    private let viewModel: NotchViewModel
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    /// Bir önceki olayda imleç aktif bölgenin içinde miydi? Genişleme yalnızca
    /// dışarıdan içeri GİRİŞ anında planlanır; böylece ESC ile kapattıktan sonra
    /// imleç pill üzerinde dursa bile ada kendiliğinden yeniden açılmaz.
    private var wasInside = false
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pollTimer: Timer?

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        // Ana kaynak: 20 Hz konum yoklaması. İzin, pencere durumu ve başlatma
        // bağlamından (Terminal / LaunchServices) tamamen bağımsız çalışır.
        // Tracking area / event monitörleri bazı bağlamlarda olay teslim etmiyor;
        // yoklama bu yüzden garanti eden temel katmandır.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.update(at: NSEvent.mouseLocation) }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        // Ek tepkisellik: hareket olayları geldiği sürece yoklamayı beklemeden işle.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in self?.update(at: NSEvent.mouseLocation) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.update(at: NSEvent.mouseLocation)
            return event
        }
        if Self.debug {
            NSLog("[hover] hazır: poll=0.05s global=%@ local=%@ hoverToExpand=%d delay=%.2f",
                  globalMonitor != nil ? "ok" : "yok", localMonitor != nil ? "ok" : "yok",
                  Preferences.shared.hoverToExpand ? 1 : 0, Preferences.shared.hoverDelay)
        }
    }

    deinit {
        pollTimer?.invalidate()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    func update(at point: NSPoint) {
        guard let screen = ScreenGeometry.targetScreen else {
            // Ekran çözülemiyorsa (yeniden yapılandırma anı) bayrakları temiz bırak;
            // aksi halde yutulan bir exit olayı isMouseInside'ı true'da kilitler.
            viewModel.isMouseInside = false
            wasInside = false
            expandWork?.cancel()
            expandWork = nil
            return
        }
        let inside = activeRegion(on: screen).contains(point)
        viewModel.isMouseInside = inside
        if Self.debug, inside != wasInside {
            NSLog("[hover] %@ point=%@ expanded=%d",
                  inside ? "girdi" : "çıktı", NSStringFromPoint(point), viewModel.isExpanded ? 1 : 0)
        }
        defer { wasInside = inside }

        if viewModel.isExpanded {
            if inside {
                collapseWork?.cancel()
                collapseWork = nil
            } else if collapseWork == nil, !viewModel.isDragHovering {
                scheduleCollapse()
            }
        } else {
            if inside, !wasInside, Preferences.shared.hoverToExpand {
                scheduleExpand()
            } else if !inside {
                expandWork?.cancel()
                expandWork = nil
            }
        }
    }

    // MARK: - Bölgeler (ekran koordinatı, sol-alt orijin)
    // topPadding: imleç ekranın en üst kenarına yapışıkken de içeride sayılsın.

    /// Kapalıyken genişlemeyi tetikleyen bölge: pill'in tamamı.
    private func triggerRect(on screen: NSScreen) -> CGRect {
        let pill = viewModel.collapsedPillSize
        return screen.topAnchoredRect(width: pill.width, height: pill.height + 4, topPadding: 4)
    }

    /// Açıkken adayı açık tutan bölge: panel + rahat bir kenar payı.
    private func keepOpenRect(on screen: NSScreen) -> CGRect {
        let size = viewModel.expandedSize
        return screen.topAnchoredRect(width: size.width + 48, height: size.height + 32, topPadding: 4)
    }

    private func activeRegion(on screen: NSScreen) -> CGRect {
        viewModel.isExpanded ? keepOpenRect(on: screen) : triggerRect(on: screen)
    }

    // MARK: - Zamanlayıcılar

    private func scheduleExpand() {
        expandWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.expandWork = nil
            guard !self.viewModel.isExpanded,
                  let screen = ScreenGeometry.targetScreen,
                  self.triggerRect(on: screen).contains(NSEvent.mouseLocation)
            else {
                if Self.debug { NSLog("[hover] expand iptal (konum/durum değişti)") }
                return
            }
            if Self.debug { NSLog("[hover] expand tetiklendi") }
            self.viewModel.expand()
        }
        expandWork = work
        // Gecikme 0 olsa bile senkron çalıştırma: expand() pencereyi yeniden
        // boyutlandırır ve bunu tracking-event callback'inin içinde (re-entrant)
        // yapmak AppKit'in enter/exit muhasebesini bozabilir.
        let delay = max(Preferences.shared.hoverDelay, 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scheduleCollapse() {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWork = nil
            guard self.viewModel.isExpanded,
                  !self.viewModel.isDragHovering,
                  let screen = ScreenGeometry.targetScreen,
                  !self.keepOpenRect(on: screen).contains(NSEvent.mouseLocation)
            else { return }
            self.viewModel.collapseNow()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Preferences.shared.collapseDelay,
            execute: work
        )
    }
}
