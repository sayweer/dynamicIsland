import AppKit
import Combine
import SwiftUI

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
            case .auto: return "Akıllı (müzik → pil)"
            case .battery: return "Pil"
            case .network: return "Ağ hızı"
            case .hidden: return "Boş"
            }
        }
    }

    enum IslandSizeMode: String, CaseIterable, Identifiable {
        case compact, normal, large
        var id: String { rawValue }
        var title: String {
            switch self {
            case .compact: return "Kompakt"
            case .normal: return "Normal"
            case .large: return "Geniş"
            }
        }
        var size: CGSize {
            switch self {
            case .compact: return CGSize(width: 620, height: 390)
            case .normal: return CGSize(width: 700, height: 430)
            case .large: return CGSize(width: 790, height: 500)
            }
        }
    }

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
    @Published var collapsedLeft: CollapsedLeftContent { didSet { save(collapsedLeft.rawValue, "collapsedLeft") } }
    @Published var collapsedRight: CollapsedRightContent { didSet { save(collapsedRight.rawValue, "collapsedRight") } }
    @Published var showEqualizer: Bool { didSet { save(showEqualizer, "showEqualizer") } }
    @Published var hapticsEnabled: Bool { didSet { save(hapticsEnabled, "hapticsEnabled") } }
    @Published var showOnNotchlessScreens: Bool { didSet { save(showOnNotchlessScreens, "showOnNotchlessScreens") } }
    @Published var clearShelfOnQuit: Bool { didSet { save(clearShelfOnQuit, "clearShelfOnQuit") } }
    @Published var enabledTabs: Set<String> { didSet { save(Array(enabledTabs).joined(separator: ","), "enabledTabs") } }

    var accentColor: Color { Color(hex: accentHex) }

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
        collapsedLeft = CollapsedLeftContent(rawValue: defaults.string(forKey: key("collapsedLeft")) ?? "") ?? .clock
        collapsedRight = CollapsedRightContent(rawValue: defaults.string(forKey: key("collapsedRight")) ?? "") ?? .auto
        showEqualizer = defaults.object(forKey: key("showEqualizer")) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: key("hapticsEnabled")) as? Bool ?? true
        showOnNotchlessScreens = defaults.object(forKey: key("showOnNotchlessScreens")) as? Bool ?? true
        clearShelfOnQuit = defaults.object(forKey: key("clearShelfOnQuit")) as? Bool
            ?? defaults.bool(forKey: SettingsKeys.clearShelfOnQuit)
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

extension Color {
    /// "#RRGGBB" biçimindeki hex dizgisinden renk üretir.
    init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
