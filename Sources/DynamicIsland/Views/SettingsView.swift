import SwiftUI
import ServiceManagement

/// Full settings window (opened from the status-bar menu).
struct SettingsView: View {
    @AppStorage(SettingsKeys.hoverToExpand) private var hoverToExpand = true
    @AppStorage(SettingsKeys.clearShelfOnQuit) private var clearShelfOnQuit = false
    @EnvironmentObject private var shelf: ShelfManager
    @EnvironmentObject private var clipboard: ClipboardManager

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Genel") {
                Toggle("Oturum açıldığında başlat", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle("İmleci çentiğe getirince genişlet", isOn: $hoverToExpand)
                Text("Kapalıyken çentiğe tıklayarak açabilirsiniz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Raf") {
                Toggle("Uygulamadan çıkarken rafı temizle", isOn: $clearShelfOnQuit)
                Button("Rafı Şimdi Temizle (\(shelf.items.count) öğe)") {
                    shelf.removeAll()
                }
            }
            Section("Pano") {
                Text("Kopyaladığınız son \(ClipboardManager.maxItems) öğe saklanır. Parola yöneticilerinden gelen gizli içerikler kaydedilmez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Pano Geçmişini Temizle (\(clipboard.items.count) öğe)") {
                    clipboard.clearAll()
                }
            }
            Section("Hakkında") {
                LabeledContent("Sürüm", value: "0.1.0")
                LabeledContent("Lisans", value: "MIT — Açık Kaynak")
                Text("NotchBox'a ücretsiz, açık kaynak bir alternatif. Müzik kontrolü, dosya rafı, AirDrop, pano geçmişi ve daha fazlası — hepsi çentikte.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 420)
    }
}

/// Compact settings shown inside the island itself.
struct SettingsQuickView: View {
    @AppStorage(SettingsKeys.hoverToExpand) private var hoverToExpand = true
    @AppStorage(SettingsKeys.clearShelfOnQuit) private var clearShelfOnQuit = false
    @EnvironmentObject private var clipboard: ClipboardManager
    @EnvironmentObject private var shelf: ShelfManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("Hızlı Ayarlar", symbol: "gearshape.fill")
            Toggle("İmleci çentiğe getirince genişlet", isOn: $hoverToExpand)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            Toggle("Çıkarken rafı temizle", isOn: $clearShelfOnQuit)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            Divider().overlay(Color.white.opacity(0.1))
            HStack(spacing: 10) {
                Button {
                    clipboard.clearAll()
                } label: {
                    Label("Panoyu temizle", systemImage: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
                Button {
                    shelf.removeAll()
                } label: {
                    Label("Rafı temizle", systemImage: "tray")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            HStack {
                Text("DynamicIsland v0.1.0 · MIT · Açık Kaynak")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
                Button {
                    NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
                } label: {
                    Label("Tüm Ayarlar…", systemImage: "arrow.up.forward.square")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Çıkış", systemImage: "power")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.8))
            }
        }
        .islandCard()
    }
}
