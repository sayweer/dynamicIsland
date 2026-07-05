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
        level = .statusBar
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

@MainActor
final class NotchWindowController {
    let panel = NotchPanel()
    private let viewModel: NotchViewModel
    private var cancellables: Set<AnyCancellable> = []

    init(viewModel: NotchViewModel, rootView: some View) {
        self.viewModel = viewModel
        let hosting = NSHostingView(rootView: AnyView(rootView))
        hosting.wantsLayer = true
        panel.contentView = hosting
        applyFrame()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyFrame() }
        }

        // Grow the window the moment the island expands; shrink it back only after
        // the collapse animation has finished.
        viewModel.$isExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                guard let self else { return }
                if expanded {
                    self.applyFrame()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        if !self.viewModel.isExpanded {
                            self.applyFrame()
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

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

        let width: CGFloat
        let height: CGFloat
        if viewModel.isExpanded {
            width = viewModel.expandedSize.width + 60
            height = viewModel.expandedSize.height + 40
        } else {
            // Tight fit: island + side content + a small margin for the shadow.
            width = viewModel.collapsedSize.width + 156 + 32
            height = viewModel.collapsedSize.height + 26
        }
        let frame = CGRect(
            x: (screen.frame.midX - width / 2).rounded(),
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
        panel.setFrame(frame, display: true)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }
}
