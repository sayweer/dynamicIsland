import AVFoundation
import AppKit
import CoreMedia
import CoreMediaIO
import SwiftUI

/// A phone whose live screen or camera can be mirrored inside the island.
struct PhoneDevice: Identifiable, Equatable {
    enum Kind { case usbScreen, continuity }
    let id: String      // AVCaptureDevice.uniqueID
    let name: String    // localizedName
    let kind: Kind
}

/// Mirrors a USB-connected iPhone's screen (Camera app viewfinder) — or a
/// Continuity Camera feed — inside the island. The capture session runs ONLY
/// while a viewer (tab or detached window) is visible; detection itself is a
/// handful of passive notification observers with ~zero cost.
@MainActor
final class PhoneMonitorManager: ObservableObject {
    @Published private(set) var authorized: Bool?
    @Published private(set) var devices: [PhoneDevice] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var isRunning = false
    @Published private(set) var isDetachedOpen = false

    var isDeviceAvailable: Bool { !devices.isEmpty }
    var selectedDevice: PhoneDevice? { devices.first { $0.id == selectedID } }
    var selectedKind: PhoneDevice.Kind? { selectedDevice?.kind }

    // Session is thread-safe; all mutations are serialized on sessionQueue while
    // the preview layer reads it on main — same discipline as CameraManager.
    nonisolated(unsafe) let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "dynamicisland.phonemonitor")

    private var viewCount = 0                    // tab + detached window refcount
    private var detectionActive = false
    private static var didOptInCMIO = false      // opt-in is rate-limited: do it once
    private var observers: [NSObjectProtocol] = []
    private var backupRefresh: DispatchWorkItem?
    private var panel: PhoneMonitorPanelController?

    // MARK: - Detection lifecycle (driven by module enable/disable)

    /// Turns passive device detection on/off. When off, no observers run, no
    /// session exists, and the CMIO opt-in (which can't be undone) simply idles.
    func setDetectionActive(_ active: Bool) {
        guard active != detectionActive else { return }
        detectionActive = active
        if active { startDetecting() } else { stopDetecting() }
    }

    private func startDetecting() {
        Self.optInCMIOOnce()
        // Warmup: the system won't deliver wasConnected notifications unless the
        // device list is queried at least once BEFORE the observers register.
        _ = Self.discover()
        registerObservers()
        refreshDevices()
        // Belt-and-suspenders: the opt-in takes effect a beat later, so re-scan
        // once in case the first pass (and its notification) missed the device.
        let work = DispatchWorkItem { [weak self] in self?.refreshDevices() }
        backupRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func stopDetecting() {
        backupRefresh?.cancel()
        removeObservers()
        closeDetachedWindow()
        viewCount = 0
        devices = []
        selectedID = nil
        updateSessionState()
    }

    // MARK: - Viewer refcount (tab onAppear/onDisappear + detached window)

    func attachView() {
        viewCount += 1
        updateSessionState()
    }

    func detachView() {
        viewCount = max(0, viewCount - 1)
        updateSessionState()
    }

    func select(_ id: String) {
        guard selectedID != id, devices.contains(where: { $0.id == id }) else { return }
        selectedID = id
        updateSessionState()
    }

    // MARK: - Detached floating window

    func openDetachedWindow() {
        if panel == nil {
            panel = PhoneMonitorPanelController(session: session) { [weak self] in
                self?.handlePanelClosed()
            }
        }
        panel?.show(aspect: selectedDeviceAspect())
        if !isDetachedOpen {
            isDetachedOpen = true
            attachView()                 // the window is itself a viewer
        }
    }

    func closeDetachedWindow() {
        panel?.close()                   // fires handlePanelClosed via delegate
    }

    private func handlePanelClosed() {
        guard isDetachedOpen else { return }
        isDetachedOpen = false
        detachView()
    }

    // MARK: - Device discovery

    private func refreshDevices() {
        let found = Self.discover()
        devices = found
        if selectedID == nil || !found.contains(where: { $0.id == selectedID }) {
            // Prefer the USB screen (records on-device) over a Continuity feed.
            selectedID = found.first { $0.kind == .usbScreen }?.id ?? found.first?.id
        }
        updateSessionState()
    }

    private func selectedDeviceAspect() -> CGSize? {
        guard let id = selectedID, let device = AVCaptureDevice(uniqueID: id) else { return nil }
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        guard dims.width > 0, dims.height > 0 else { return nil }
        return CGSize(width: CGFloat(dims.width), height: CGFloat(dims.height))
    }

    /// Discovers only phone sources — USB screen mirrors (muxed) and Continuity
    /// Cameras. Plain USB webcams are intentionally excluded.
    private static func discover() -> [PhoneDevice] {
        let types: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            types = [.external, .continuityCamera]
        } else {
            types = [.externalUnknown]
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: nil, position: .unspecified)
        return discovery.devices.compactMap { device in
            let kind: PhoneDevice.Kind
            if device.hasMediaType(.muxed) {
                kind = .usbScreen
            } else if #available(macOS 14.0, *), device.deviceType == .continuityCamera {
                kind = .continuity
            } else {
                return nil
            }
            return PhoneDevice(id: device.uniqueID, name: device.localizedName, kind: kind)
        }
    }

    // MARK: - Session state (single decision point)

    private func updateSessionState() {
        let wantsPreview = viewCount > 0 && selectedID != nil
        guard wantsPreview else {
            stopSession()
            return
        }
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
            stopSession()
        }
    }

    private func startSession() {
        guard let id = selectedID else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = AVCaptureDevice(uniqueID: id) else {
                Task { @MainActor in self.isRunning = false }
                return
            }
            // Reconfigure only when the target device changed (first setup, a
            // reconnect, or a source switch) so a stale input can't show black.
            // Don't touch sessionPreset: muxed screen devices may reject presets.
            let current = (self.session.inputs.first as? AVCaptureDeviceInput)?.device
            if current?.uniqueID != device.uniqueID {
                self.session.beginConfiguration()
                self.session.inputs.forEach { self.session.removeInput($0) }
                if let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                self.session.commitConfiguration()
            }
            guard !self.session.inputs.isEmpty else {
                Task { @MainActor in self.isRunning = false }
                return
            }
            if !self.session.isRunning { self.session.startRunning() }
            Task { @MainActor in self.isRunning = true }
        }
    }

    private func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            // Drop the input too, so a reconnect always rebuilds cleanly.
            if !self.session.inputs.isEmpty {
                self.session.beginConfiguration()
                self.session.inputs.forEach { self.session.removeInput($0) }
                self.session.commitConfiguration()
            }
            Task { @MainActor in self.isRunning = false }
        }
    }

    // MARK: - Observers

    private func registerObservers() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        let refresh: (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.refreshDevices() }
        }
        observers.append(nc.addObserver(
            forName: .AVCaptureDeviceWasConnected, object: nil, queue: .main, using: refresh))
        observers.append(nc.addObserver(
            forName: .AVCaptureDeviceWasDisconnected, object: nil, queue: .main, using: refresh))
        observers.append(nc.addObserver(
            forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleRuntimeError() }
            })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refresh))
    }

    private func removeObservers() {
        for token in observers {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        observers = []
    }

    /// After a runtime error (device yanked mid-stream, USB re-enumeration),
    /// rebuild once if a viewer is still watching.
    private func handleRuntimeError() {
        guard viewCount > 0 else { return }
        stopSession()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshDevices()
        }
    }

    // MARK: - CoreMediaIO opt-in

    /// Exposes USB screen-capture devices (iPhone/iPad) to AVFoundation — the
    /// same switch QuickTime and OBS flip. Rate-limited by the OS, so once only.
    private static func optInCMIOOnce() {
        guard !didOptInCMIO else { return }
        didOptInCMIO = true
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<UInt32>.size), &allow)
    }
}
