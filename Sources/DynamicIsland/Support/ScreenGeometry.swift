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
