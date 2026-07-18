import SwiftUI

/// The full island panel: header beside the notch, tab strip, active tab content.
struct ExpandedView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var stats: SystemStats
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        VStack(spacing: 6) {
            header
                .frame(height: max(vm.collapsedSize.height - 4, 24))
            TabStrip()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(vm.activeTab)
                .transition(.opacity)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Tek animasyon kaynağı: sekme değişince hem TabStrip kapsülü kayar
        // (matchedGeometry) hem içerik crossfade olur.
        .animation(Motion.standard, value: vm.activeTab)
        .onChange(of: prefs.enabledTabs) { _ in
            if !prefs.isTabEnabled(vm.activeTab) {
                vm.activeTab = .home
            }
        }
    }

    private var header: some View {
        HStack {
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.weekday(.wide).day().month())
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            // Physical notch sits here — keep it clear.
            Color.clear.frame(width: vm.collapsedSize.width * 0.6, height: 1)
            Spacer()
            HStack(spacing: 10) {
                Label(NetworkMonitor.format(network.downloadBps), systemImage: "arrow.down")
                    .labelStyle(CompactStatLabelStyle())
                if let level = stats.batteryLevel {
                    Label(
                        "%\(level)",
                        systemImage: stats.batteryCharging ? "bolt.fill" : "battery.100"
                    )
                    .labelStyle(CompactStatLabelStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.activeTab {
        case .home: HomeView()
        case .shelf: ShelfView()
        case .clipboard: ClipboardView()
        case .tools: ToolsView()
        case .calendar: CalendarTabView()
        case .camera: CameraTabView()
        case .phoneMonitor: PhoneMonitorTabView()
        case .browser: BrowserView()
        case .notes: NotesTabView()
        case .settings: SettingsQuickView()
        }
    }
}

struct CompactStatLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
                .font(.system(size: 8, weight: .semibold))
            configuration.title
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(.white.opacity(0.55))
    }
}

struct TabStrip: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var prefs: Preferences
    @Namespace private var tabNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(prefs.visibleTabs) { tab in
                Button {
                    vm.activeTab = tab
                    prefs.performHaptic(.generic)
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            vm.activeTab == tab ? prefs.accentColor : .white.opacity(0.45)
                        )
                        .frame(width: 34, height: 24)
                        .background {
                            // Aktif kapsül sekmeler arasında kayar (ani belirme yerine).
                            if vm.activeTab == tab {
                                Capsule()
                                    .fill(Color.white.opacity(0.12))
                                    .matchedGeometryEffect(id: "activeTab", in: tabNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(IslandButtonStyle())
                .help(tab.title)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(vm.activeTab == tab ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.05)))
    }
}

// MARK: - Shared card styling

struct IslandCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    func islandCard() -> some View {
        modifier(IslandCard())
    }
}

struct CardTitle: View {
    let text: String
    let symbol: String
    var tint: Color = .white.opacity(0.6)

    init(_ text: String, symbol: String, tint: Color = .white.opacity(0.6)) {
        self.text = text
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint)
    }
}
