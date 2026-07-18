import SwiftUI
import ServiceManagement

/// İlk açılışta tek seferlik karşılama. Uygulama accessory olduğu için normalde
/// hiçbir pencere görünmez — ada nerede yaşar, nasıl açılır, nasıl çıkılır
/// burada öğretilir; yoksa kullanıcı uygulamanın çalıştığını fark edemeyebilir.
struct WelcomeView: View {
    @EnvironmentObject private var prefs: Preferences
    let onStart: () -> Void

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 18) {
            MiniIslandGlyph(tint: prefs.accentColor)
                .frame(width: 76, height: 52)

            VStack(spacing: 4) {
                Text("Dynamic Island'a Hoş Geldiniz")
                    .font(.title3.weight(.bold))
                Text("Uygulama ekranın en üstünde, çentiğin içinde yaşar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                row(
                    symbol: "cursorarrow.motionlines",
                    title: "İmleci çentiğe götürün",
                    detail: "Ada kendiliğinden açılır; ESC veya dışarı tıklama kapatır."
                )
                row(
                    symbol: "tray.and.arrow.down",
                    title: "Dosyaları çentiğe sürükleyin",
                    detail: "Raf açılır: dosyalar orada bekler, dışarı sürükleyebilir veya AirDrop'layabilirsiniz."
                )
                row(
                    symbol: "sparkles.rectangle.stack",
                    title: "Menü çubuğu simgesi",
                    detail: "Ayarlar ve çıkış her zaman oradadır."
                )
            }
            .padding(.vertical, 4)

            Toggle("Oturum açıldığında başlat", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            Button("Başla") { onStart() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 420)
    }

    private func row(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(prefs.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
