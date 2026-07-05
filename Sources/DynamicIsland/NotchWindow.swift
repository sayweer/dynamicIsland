import AppKit
import SwiftUI

/// Borderless, transparent, always-on-top panel anchored to the top-center of the screen.
/// The window is always sized for the expanded island; fully transparent pixels
/// pass mouse events through to windows below.
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
        registerForDraggedTypes([.fileURL, .string, .tiff, .png, .URL])
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchWindowController {
    let panel = NotchPanel()
    private let viewModel: NotchViewModel

    init(viewModel: NotchViewModel, rootView: some View) {
        self.viewModel = viewModel
        let hosting = NSHostingView(rootView: AnyView(rootView))
        hosting.wantsLayer = true
        panel.contentView = hosting
        reposition()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }

    func reposition() {
        guard let screen = ScreenGeometry.targetScreen else { return }
        viewModel.refreshGeometry()
        let size = viewModel.expandedSize
        let width = max(size.width, viewModel.collapsedSize.width) + 60
        let height = size.height + 40
        let frame = CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
        panel.setFrame(frame, display: true)
    }
}
