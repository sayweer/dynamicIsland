import AppKit
import AVFoundation
import SwiftUI

/// A floating, resizable window that mirrors the same capture session as the
/// island tab via a second preview layer (one session feeds many layers at
/// ~zero extra cost). Kept aspect-locked to the device's native ratio.
@MainActor
final class PhoneMonitorPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let session: AVCaptureSession
    private let onClose: () -> Void

    init(session: AVCaptureSession, onClose: @escaping () -> Void) {
        self.session = session
        self.onClose = onClose
        super.init()
    }

    /// Shows the window, sizing it to `aspect` (falls back to a portrait phone).
    func show(aspect: CGSize?) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let ratio = aspect ?? CGSize(width: 9, height: 19.5)
        let height: CGFloat = 720
        let width = (height * ratio.width / ratio.height).rounded()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .black
        panel.contentAspectRatio = NSSize(width: ratio.width, height: ratio.height)
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: CameraPreview(session: session, videoGravity: .resizeAspect, mirrored: false)
        )

        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.maxX - width - 24, y: vf.midY - height / 2))
        } else {
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() {
        panel?.close()
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        onClose()
    }
}
