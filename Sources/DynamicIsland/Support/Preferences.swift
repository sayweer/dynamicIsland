import AppKit
import Combine
import SwiftUI

/// Uygulama kimliği — sürüm tek kaynaktan (Info.plist) okunur.
enum AppInfo {
    static let version: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }()
}

/// Kullanıcı tercihlerinin tek kaynağı. UserDefaults'a yazar, tüm arayüz buradan okur.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    enum CollapsedLeftContent: String, CaseIterable, Identifiable {
        case clock, date, hidden
        var id: String { rawValue }
        var title: String {
            switch self {
            case .clock: return "Saat"
            case .date: return "Tarih"
            case .hidden: return "Boş"
            }
        }
    }

    enum CollapsedRightContent: String, CaseIterable, Identifiable {
        case auto, battery, network, hidden
        var id: String { rawValue }
        var title: String {
            switch self {
            case .auto: return "Akıllı"
            case .battery: return "Pil"
            case .network: return "Ağ"
            case .hidden: return "Boş"
            }
        }
    }

    enum IslandSizeMode: String, CaseIterable, Identifiable {
        case compact, normal, large, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .compact: return "Kompakt"
            case .normal: return "Normal"
            case .large: return "Geniş"
            case .custom: return "Özel"
            }
        }
        var size: CGSize {
            switch self {
            case .compact: return CGSize(width: 620, height: 390)
            case .normal: return CGSize(width: 700, height: 430)
            case .large: return CGSize(width: 790, height: 500)
            // .custom'ın gerçek boyutu expandedPanelSize'dan gelir; burası yalnız güvenli geri dönüş.
            case .custom: return Self.normal.size
            }
        }
    }

    enum AnimationSpeed: String, CaseIterable, Identifiable {
        case calm, normal, fast
        var id: String { rawValue }
        var title: String {
            switch self {
            case .calm: return "Sakin"
            case .normal: return "Normal"
            case .fast: return "Hızlı"
            }
        }
        /// Yay animasyonlarının response süresine uygulanan çarpan.
        var factor: Double {
            switch self {
            case .calm: return 1.35
            case .normal: return 1.0
            case .fast: return 0.7
            }
        }
    }

    /// Özel panel boyutu için izin verilen aralıklar.
    static let panelWidthRange: ClosedRange<Double> = 560...900
    static let panelHeightRange: ClosedRange<Double> = 340...560
    static let cornerRadiusRange: ClosedRange<Double> = 14...36

    struct AccentOption: Identifiable, Equatable {
        let name: String
        let hex: String
        var id: String { hex }
        var color: Color { Color(hex: hex) }
    }

    static let accentPalette: [AccentOption] = [
        AccentOption(name: "Yeşil", hex: "#30D158"),
        AccentOption(name: "Mavi", hex: "#0A84FF"),
        AccentOption(name: "Mor", hex: "#BF5AF2"),
        AccentOption(name: "Pembe", hex: "#FF375F"),
        AccentOption(name: "Turuncu", hex: "#FF9F0A"),
        AccentOption(name: "Turkuaz", hex: "#64D2FF"),
    ]

    // MARK: - Stored preferences

    @Published var hoverToExpand: Bool { didSet { save(hoverToExpand, "hoverToExpand") } }
    @Published var hoverDelay: Double { didSet { save(hoverDelay, "hoverDelay") } }
    @Published var collapseDelay: Double { didSet { save(collapseDelay, "collapseDelay") } }
    @Published var accentHex: String { didSet { save(accentHex, "accentHex") } }
    @Published var islandSizeMode: IslandSizeMode { didSet { save(islandSizeMode.rawValue, "islandSizeMode") } }
    @Published var customPanelWidth: Double { didSet { save(customPanelWidth, "customPanelWidth") } }
    @Published var customPanelHeight: Double { didSet { save(customPanelHeight, "customPanelHeight") } }
    @Published var expandedCornerRadius: Double { didSet { save(expandedCornerRadius, "expandedCornerRadius") } }
    @Published var animationSpeed: AnimationSpeed { didSet { save(animationSpeed.rawValue, "animationSpeed") } }
    @Published var collapsedLeft: CollapsedLeftContent { didSet { save(collapsedLeft.rawValue, "collapsedLeft") } }
    @Published var collapsedRight: CollapsedRightContent { didSet { save(collapsedRight.rawValue, "collapsedRight") } }
    @Published var showEqualizer: Bool { didSet { save(showEqualizer, "showEqualizer") } }
    @Published var hapticsEnabled: Bool { didSet { save(hapticsEnabled, "hapticsEnabled") } }
    @Published var showOnNotchlessScreens: Bool { didSet { save(showOnNotchlessScreens, "showOnNotchlessScreens") } }
    @Published var clearShelfOnQuit: Bool { didSet { save(clearShelfOnQuit, "clearShelfOnQuit") } }
    @Published var clipboardLimit: Int { didSet { save(clipboardLimit, "clipboardLimit") } }
    @Published var enabledTabs: Set<String> { didSet { save(Array(enabledTabs).joined(separator: ","), "enabledTabs") } }

    /// Pano geçmişinde saklanacak öğe sayısı seçenekleri.
    static let clipboardLimitOptions = [10, 20, 50]

    var accentColor: Color { Color(hex: accentHex) }

    /// Genişlemiş panelin etkin boyutu: preset ya da kullanıcının özel değerleri.
    var expandedPanelSize: CGSize {
        guard islandSizeMode == .custom else { return islandSizeMode.size }
        return CGSize(
            width: customPanelWidth.clamped(to: Self.panelWidthRange),
            height: customPanelHeight.clamped(to: Self.panelHeightRange)
        )
    }

    /// Aç/kapa yay animasyonları — hız tercihine göre ölçeklenir.
    private var collapseResponse: Double { 0.35 * animationSpeed.factor }
    var expandSpring: Animation {
        .spring(response: 0.38 * animationSpeed.factor, dampingFraction: 0.82)
    }
    var collapseSpring: Animation {
        .spring(response: collapseResponse, dampingFraction: 0.85)
    }

    /// Home ve Ayarlar her zaman açık kalır; diğerleri kapatılabilir.
    static let lockedTabs: Set<String> = [IslandTab.home.rawValue, IslandTab.settings.rawValue]

    func isTabEnabled(_ tab: IslandTab) -> Bool {
        Self.lockedTabs.contains(tab.rawValue) || enabledTabs.contains(tab.rawValue)
    }

    func setTab(_ tab: IslandTab, enabled: Bool) {
        guard !Self.lockedTabs.contains(tab.rawValue) else { return }
        if enabled {
            enabledTabs.insert(tab.rawValue)
        } else {
            enabledTabs.remove(tab.rawValue)
        }
    }

    var visibleTabs: [IslandTab] {
        IslandTab.allCases.filter { isTabEnabled($0) }
    }

    // MARK: - Init / persistence

    private let defaults = UserDefaults.standard
    private var loading = true

    private init() {
        func key(_ name: String) -> String { "pref.\(name)" }
        hoverToExpand = defaults.object(forKey: key("hoverToExpand")) as? Bool ?? true
        hoverDelay = defaults.object(forKey: key("hoverDelay")) as? Double ?? 0.1
        collapseDelay = defaults.object(forKey: key("collapseDelay")) as? Double ?? 0.4
        accentHex = defaults.string(forKey: key("accentHex")) ?? "#30D158"
        islandSizeMode = IslandSizeMode(rawValue: defaults.string(forKey: key("islandSizeMode")) ?? "") ?? .normal
        customPanelWidth = (defaults.object(forKey: key("customPanelWidth")) as? Double ?? 700)
            .clamped(to: Self.panelWidthRange)
        customPanelHeight = (defaults.object(forKey: key("customPanelHeight")) as? Double ?? 430)
            .clamped(to: Self.panelHeightRange)
        expandedCornerRadius = (defaults.object(forKey: key("expandedCornerRadius")) as? Double ?? 24)
            .clamped(to: Self.cornerRadiusRange)
        animationSpeed = AnimationSpeed(rawValue: defaults.string(forKey: key("animationSpeed")) ?? "") ?? .normal
        collapsedLeft = CollapsedLeftContent(rawValue: defaults.string(forKey: key("collapsedLeft")) ?? "") ?? .clock
        collapsedRight = CollapsedRightContent(rawValue: defaults.string(forKey: key("collapsedRight")) ?? "") ?? .auto
        showEqualizer = defaults.object(forKey: key("showEqualizer")) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: key("hapticsEnabled")) as? Bool ?? true
        showOnNotchlessScreens = defaults.object(forKey: key("showOnNotchlessScreens")) as? Bool ?? true
        clearShelfOnQuit = defaults.object(forKey: key("clearShelfOnQuit")) as? Bool
            ?? defaults.bool(forKey: SettingsKeys.clearShelfOnQuit)
        let savedLimit = defaults.object(forKey: key("clipboardLimit")) as? Int ?? 20
        clipboardLimit = Self.clipboardLimitOptions.contains(savedLimit) ? savedLimit : 20
        if let raw = defaults.string(forKey: key("enabledTabs")) {
            enabledTabs = Set(raw.split(separator: ",").map(String.init))
        } else {
            enabledTabs = Set(IslandTab.allCases.map(\.rawValue))
        }
        loading = false
    }

    private func save(_ value: Any, _ name: String) {
        guard !loading else { return }
        defaults.set(value, forKey: "pref.\(name)")
    }

    func performHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
        guard hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension Color {
    /// "#RRGGBB" biçimindeki hex dizgisinden renk üretir. Geçersiz/eksik hex
    /// sessizce siyaha düşmesin diye varsayılan accent'e (#30D158) geri döner.
    init(hex: String) {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        let valid = cleaned.count == 6 && Scanner(string: cleaned).scanHexInt64(&value)
        let rgb = valid ? value : 0x30D158
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Rengi "#RRGGBB" biçimine çevirir (ColorPicker seçimini accentHex'e yazmak için).
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
