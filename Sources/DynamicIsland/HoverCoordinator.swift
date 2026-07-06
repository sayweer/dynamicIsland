import AppKit

/// Hover tanılaması: `pref.debugHover` (defaults) ya da `--debug-hover` ile açılır,
/// /tmp/dynamicisland-hover.log dosyasına yazar. Amaç: kullanıcının makinesinde,
/// gerçek kullanım sırasında hangi katmanın (timer kadansı / bölge kararı /
/// expand yürütmesi / pencere) durduğunu kanıtlamak. Kapalıyken maliyeti sıfıra yakın.
@MainActor
enum HoverDiag {
    static let enabled: Bool =
        ProcessInfo.processInfo.arguments.contains("--debug-hover")
        || UserDefaults.standard.bool(forKey: "pref.debugHover")

    private static let handle: FileHandle? = {
        guard enabled else { return nil }
        let path = "/tmp/dynamicisland-hover.log"
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    static func log(_ message: String) {
        guard enabled, let handle else { return }
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        let line = String(format: "%.2f [%@] %@\n", Date().timeIntervalSinceReferenceDate, front, message)
        handle.write(Data(line.utf8))
    }
}

/// Poll kuyruğunda yaşayan paylaşımlı durum. `region` ana aktörden yazılır,
/// poll kuyruğundan okunur (kilitli); diğer alanlara YALNIZCA poll kuyruğu dokunur.
final class HoverPollState: @unchecked Sendable {
    private let lock = NSLock()
    private var _region: CGRect = .zero

    /// O anki aktif bölgenin (trigger ya da keep-open) ekran dikdörtgeni.
    var region: CGRect {
        get { lock.lock(); defer { lock.unlock() }; return _region }
        set { lock.lock(); defer { lock.unlock() }; _region = newValue }
    }

    // Poll kuyruğuna özel sayaçlar (kilitsiz — tek kuyruk).
    var lastInside = false
    var tickCount = 0
    var lastTickAt: CFAbsoluteTime = 0
    var maxTickGap: Double = 0
}

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
    private let viewModel: NotchViewModel
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    /// Bir önceki olayda imleç aktif bölgenin içinde miydi? Genişleme yalnızca
    /// dışarıdan içeri GİRİŞ anında planlanır; böylece ESC ile kapattıktan sonra
    /// imleç pill üzerinde dursa bile ada kendiliğinden yeniden açılmaz.
    private var wasInside = false
    // Yalnızca init'te (MainActor) atanır, deinit'te (başka erişim yokken)
    // serbest bırakılır; nonisolated deinit'ten güvenle erişilir.
    private nonisolated(unsafe) var globalMonitor: Any?
    private nonisolated(unsafe) var localMonitor: Any?
    private var pollTimer: DispatchSourceTimer?
    private let pollState = HoverPollState()
    /// Ana kuyruk, uygulama arka plandayken sistem tarafından yavaşlatılabildiği
    /// için yoklama ANA KUYRUK DIŞINDA döner (Apple forum 125371'deki kanıtlı çözüm).
    private let pollQueue = DispatchQueue(label: "dynamicisland.hover.poll", qos: .userInteractive)

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        // Ana kaynak: 20 Hz konum yoklaması. İzin, pencere durumu, başlatma
        // bağlamı ve ana döngünün yoğunluğundan bağımsız çalışır.
        // Sıcak yol yalnızca konum + dikdörtgen testi yapar; ana aktöre
        // durum değişiminde ya da saniyede bir (güvenlik) uğrar.
        let state = pollState
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: pollQueue)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05, leeway: .milliseconds(10))
        timer.setEventHandler { [weak self, state] in
            let now = CFAbsoluteTimeGetCurrent()
            if state.lastTickAt > 0 {
                state.maxTickGap = max(state.maxTickGap, now - state.lastTickAt)
            }
            state.lastTickAt = now
            state.tickCount += 1

            let point = NSEvent.mouseLocation
            let inside = state.region.contains(point)
            let changed = inside != state.lastInside
            state.lastInside = inside

            if HoverDiag.enabled, state.tickCount % 100 == 0 {
                // Poll-kuyruğu alanlarını ana aktöre DEĞER olarak taşı; canlı
                // referans okuması bir sonraki tick'in yazmasıyla yarışırdı.
                let count = state.tickCount
                let gap = Int(state.maxTickGap * 1000)
                state.maxTickGap = 0
                Task { @MainActor in
                    HoverDiag.log("hb #\(count) maxGap=\(gap)ms point=\(NSStringFromPoint(point))")
                }
            }
            // Durum değişiminde hemen, değişmese de saniyede bir ana aktörde
            // yetkili değerlendirme (bölge önbelleği bayatlamışsa düzeltir).
            // Konum ana aktörde TAZE okunur; kuyruğa alınan bayat bir point
            // güncel kararı geri sarıp collapse'ı yanlışlıkla iptal edemesin.
            if changed || state.tickCount % 20 == 0 {
                Task { @MainActor in self?.update(at: NSEvent.mouseLocation) }
            }
        }
        timer.resume()
        pollTimer = timer

        // Ek tepkisellik: hareket olayları geldiği sürece yoklamayı beklemeden işle.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in self?.update(at: NSEvent.mouseLocation) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.update(at: NSEvent.mouseLocation)
            return event
        }
        HoverDiag.log("hazır: poll=0.05s(strict, ayrı kuyruk) global=\(globalMonitor != nil) "
            + "local=\(localMonitor != nil) hoverToExpand=\(Preferences.shared.hoverToExpand) "
            + "delay=\(Preferences.shared.hoverDelay)")
    }

    deinit {
        pollTimer?.cancel()
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
            pollState.region = .zero
            return
        }
        let region = activeRegion(on: screen)
        pollState.region = region // poll kuyruğunun sıcak yol önbelleği
        let inside = region.contains(point)
        viewModel.isMouseInside = inside
        if HoverDiag.enabled, inside != wasInside {
            HoverDiag.log("\(inside ? "girdi" : "çıktı") point=\(NSStringFromPoint(point)) "
                + "expanded=\(viewModel.isExpanded)")
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
                HoverDiag.log("expand planlandı (delay=\(Preferences.shared.hoverDelay))")
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
                HoverDiag.log("expand İPTAL (konum/durum değişti)")
                return
            }
            HoverDiag.log("expand TETİKLENDİ")
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
            HoverDiag.log("collapse tetiklendi")
            self.viewModel.collapseNow()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Preferences.shared.collapseDelay,
            execute: work
        )
    }
}
