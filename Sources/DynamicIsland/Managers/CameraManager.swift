import AVFoundation
import AppKit
import Combine
import SwiftUI

/// Webcam mirror shown inside the island. The session only runs while the tab is visible.
@MainActor
final class CameraManager: ObservableObject {
    @Published private(set) var authorized: Bool?
    @Published private(set) var isRunning = false

    let session = AVCaptureSession()
    private var configured = false
    private let sessionQueue = DispatchQueue(label: "dynamicisland.camera")

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in
                    self?.authorized = granted
                    if granted { self?.startSession() }
                }
            }
        default:
            authorized = false
        }
    }

    private func startSession() {
        let needsConfiguration = !configured
        configured = true
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if needsConfiguration {
                self.session.beginConfiguration()
                self.session.sessionPreset = .medium
                if let device = AVCaptureDevice.default(for: .video),
                   let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                self.session.commitConfiguration()
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            Task { @MainActor in self.isRunning = true }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            Task { @MainActor in self.isRunning = false }
        }
    }
}

/// AppKit-backed preview layer, mirrored like a real mirror.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(layer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer?.sublayers?.first?.frame = nsView.bounds
    }
}
