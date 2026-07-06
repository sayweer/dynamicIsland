import AppKit
import Combine
import SwiftUI

/// Borderless, transparent, always-on-top panel anchored to the top-center of the screen.
/// Sized tightly around the collapsed island; grows only while expanded so it can
/// never block clicks elsewhere on the screen.
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
        // kanıtlanmış değeri) durum öğeleri ve Tahoe tam ekran şeridiyle
        // z-sırası çekişmesini önler.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 8)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Panel key olduğunda mouseMoved olayları local monitöre de ulaşsın.
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that reports every mouse enter/move/exit over the panel,
/// independent of SwiftUI's own (animation-sensitive) hover tracking.
final class TrackingHostingView: NSHostingView<AnyView> {
    var onMouse: (() -> Void)?
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // .inVisibleRect alanı otomatik olarak görünür sınırlara bağlar;
        // pencere her boyut değiştirdiğinde yeniden kurmak gerekmez.
        guard hoverArea == nil else { return }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onMouse?()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onMouse?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouse?()
    }
}

@MainActor
final class NotchWindowController {
    let panel = NotchPanel()
    private let viewModel: NotchViewModel
    private var cancellables: Set<AnyCancellable> = []
    private let hover: HoverCoordinator

    init(viewModel: NotchViewModel, rootView: some View) {
        self.viewModel = viewModel
        self.hover = HoverCoordinator(viewModel: viewModel)
        let hosting = TrackingHostingView(rootView: AnyView(rootView))
        hosting.wantsLayer = true
        // The window frame is managed solely by applyFrame; don't let SwiftUI
        // sizing constraints resize the window behind our back.
        hosting.sizingOptions = []
        hosting.onMouse = { [weak self] in
            self?.hover.update(at: NSEvent.mouseLocation)
        }
        panel.contentView = hosting
        applyFrame()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Hedef ekran kaybolduysa (kapak kapandı / ekran ayrıldı) adayı
                // kapat; panel geri geldiğinde açık takılı kalmasın.
                if ScreenGeometry.targetScreen == nil, self.viewModel.isExpanded {
                    self.viewModel.collapseNow()
                }
                self.applyFrame()
            }
        }

        // Grow the window the moment the island expands; shrink it back only after
        // the collapse animation has finished. @Published emits during willSet, so
        // the property itself is stale here — always use the emitted value.
        viewModel.$isExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                guard let self else { return }
                if expanded {
                    self.applyFrame(expanded: true)
                } else {
                    let delay = Preferences.shared.windowShrinkDelay
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        if !self.viewModel.isExpanded {
                            self.applyFrame(expanded: false)
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

    func applyFrame(expanded: Bool? = nil) {
        let isExpanded = expanded ?? viewModel.isExpanded
        guard let screen = ScreenGeometry.targetScreen else {
            panel.orderOut(nil)
            return
        }
        if !screen.hasNotch && !Preferences.shared.showOnNotchlessScreens {
            panel.orderOut(nil)
            return
        }
        viewModel.refreshGeometry()

        let width: CGFloat
        let height: CGFloat
        if isExpanded {
            width = viewModel.expandedSize.width + 60
            height = viewModel.expandedSize.height + 40
        } else {
            // Tight fit: pill + a small margin for the shadow.
            width = viewModel.collapsedPillSize.width + 32
            height = viewModel.collapsedPillSize.height + 26
        }
        // Fiziksel çentik ekran merkezinden yarım nokta kayık raporlanabilir
        // (auxiliary alanlar asimetrik); pill'i ekran yerine çentiğe hizala.
        // AppKit pencere origin'ini tam noktaya sabitlediği için kalan ≤0.5pt
        // sapma kaçınılmaz ve görünmezdir.
        var frame = screen.topAnchoredRect(width: width, height: height)
        frame.origin.x = frame.origin.x.rounded()
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
            HoverDiag.log("pencere -> \(NSStringFromRect(frame))")
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }
}
