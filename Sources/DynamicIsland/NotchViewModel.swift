import AppKit
import Combine
import SwiftUI

enum IslandTab: String, CaseIterable, Identifiable {
    case home, shelf, clipboard, tools, calendar, camera, browser, notes, settings

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .shelf: return "tray.full.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .tools: return "timer"
        case .calendar: return "calendar"
        case .camera: return "web.camera.fill"
        case .browser: return "safari.fill"
        case .notes: return "note.text"
        case .settings: return "gearshape.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return "Ana Sayfa"
        case .shelf: return "Raf"
        case .clipboard: return "Pano"
        case .tools: return "Araçlar"
        case .calendar: return "Takvim"
        case .camera: return "Ayna"
        case .browser: return "Tarayıcı"
        case .notes: return "Notlar"
        case .settings: return "Ayarlar"
        }
    }
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var isExpanded = false
    @Published var activeTab: IslandTab = .home
    @Published var isDragHovering = false
    @Published var collapsedSize = CGSize(width: 196, height: 32)

    /// Set while the pointer sits inside the island so we can delay collapse.
    /// Hiçbir view okumadığı için yayınlanmaz (her mouse hareketinde
    /// objectWillChange tetiklememek için düz property).
    var isMouseInside = false

    var expandedSize: CGSize { Preferences.shared.expandedPanelSize }

    /// Kapalı moddaki görünür pill: çentik + iki yandaki içerik bölgeleri.
    /// Pencere, çizim ve hover tetikleme bölgesi hep bu boyuttan türetilir.
    var collapsedPillSize: CGSize {
        CGSize(width: collapsedSize.width + 156, height: collapsedSize.height)
    }

    private var collapseWorkItem: DispatchWorkItem?

    func refreshGeometry() {
        if let screen = ScreenGeometry.targetScreen {
            collapsedSize = screen.islandSize
        }
    }

    func expand(tab: IslandTab? = nil) {
        collapseWorkItem?.cancel()
        if let tab { activeTab = tab }
        if !Preferences.shared.isTabEnabled(activeTab) {
            activeTab = .home
        }
        guard !isExpanded else { return }
        Preferences.shared.performHaptic()
        withAnimation(Preferences.shared.expandSpring) {
            isExpanded = true
        }
    }

    func collapse(afterDelay delay: TimeInterval = 0) {
        collapseWorkItem?.cancel()
        guard isExpanded else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isMouseInside, !self.isDragHovering else { return }
            withAnimation(Preferences.shared.collapseSpring) {
                self.isExpanded = false
            }
        }
        collapseWorkItem = work
        if delay <= 0 {
            work.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    func collapseNow() {
        collapseWorkItem?.cancel()
        isMouseInside = false
        isDragHovering = false
        withAnimation(Preferences.shared.collapseSpring) {
            isExpanded = false
        }
    }
}
