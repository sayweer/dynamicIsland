import AppKit

enum ScreenGeometry {
    /// The screen that hosts the island: prefer a screen with a physical notch,
    /// otherwise fall back to the main screen (simulated notch).
    static var targetScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.hasNotch }) ?? NSScreen.main
    }
}

extension NSScreen {
    var hasNotch: Bool {
        safeAreaInsets.top > 0
    }

    /// The physical notch rect in screen coordinates, or nil when the screen has no notch.
    var notchRect: CGRect? {
        guard hasNotch,
              let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea else { return nil }
        let width = frame.width - left.width - right.width
        return CGRect(
            x: frame.minX + left.width,
            y: frame.maxY - safeAreaInsets.top,
            width: width,
            height: safeAreaInsets.top
        )
    }

    /// Adanın yatay merkezi: varsa fiziksel çentiğin ortası, yoksa ekran ortası.
    /// Pencere konumu ve hover bölgeleri aynı merkezi kullanmak zorunda.
    var notchCenterX: CGFloat {
        notchRect?.midX ?? frame.midX
    }

    /// Ekranın üst kenarına yapışık, çentiğe ortalanmış dikdörtgen
    /// (pencere frame'i ve hover bölgeleri için ortak kalıp).
    func topAnchoredRect(width: CGFloat, height: CGFloat, topPadding: CGFloat = 0) -> CGRect {
        CGRect(
            x: notchCenterX - width / 2,
            y: frame.maxY - height,
            width: width,
            height: height + topPadding
        )
    }

    /// Size of the collapsed island. Matches the physical notch when present,
    /// otherwise a simulated Dynamic Island pill.
    var islandSize: CGSize {
        if let notch = notchRect {
            return CGSize(width: notch.width, height: notch.height)
        }
        let menuBarHeight = frame.maxY - visibleFrame.maxY
        return CGSize(width: 196, height: max(menuBarHeight, 30))
    }
}
