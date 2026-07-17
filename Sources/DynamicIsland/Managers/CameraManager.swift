import AVFoundation
import AppKit
import Combine
import SwiftUI

/// Webcam mirror shown inside the island. The session only runs while the tab is visible.
@MainActor
final class CameraManager: ObservableObject {
    @Published private(set) var authorized: Bool?
    @Published private(set) var isRunning = false
    /// İzin var ama kullanılabilir kamera cihazı yok / input eklenemedi.
    @Published private(set) var unavailable = false

    // AVCaptureSession thread-safe ve tüm mutasyonları sessionQueue'da seri;
    // önizleme katmanı da main'de okur — bu yüzden aktör-izole değil.
    nonisolated(unsafe) let session = AVCaptureSession()
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
        // Tüm session erişimi tek seri kuyrukta (yarış yok). Mevcut input'un cihazı
        // güncel varsayılan kameradan farklıysa (ilk kurulum, kopma, cihaz değişimi)
        // yeniden yapılandır — kopmuş kameranın stale input'u siyah görüntü vermesin.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = AVCaptureDevice.default(for: .video) else {
                Task { @MainActor in
                    self.unavailable = true
                    self.isRunning = false
                }
                return
            }
            let currentDevice = (self.session.inputs.first as? AVCaptureDeviceInput)?.device
            if currentDevice != device {
                self.session.beginConfiguration()
                self.session.inputs.forEach { self.session.removeInput($0) }
                self.session.sessionPreset = .medium
                if let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                self.session.commitConfiguration()
            }
            guard !self.session.inputs.isEmpty else {
                Task { @MainActor in
                    self.unavailable = true
                    self.isRunning = false
                }
                return
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            Task { @MainActor in
                self.unavailable = false
                self.isRunning = true
            }
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
