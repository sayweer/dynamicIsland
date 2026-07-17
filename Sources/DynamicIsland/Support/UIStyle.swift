import SwiftUI

/// Paylaşılan hareket (animasyon) token'ları. Tüm arayüz bunları kullanır ki
/// tempo tutarlı olsun; animationSpeed çarpanına da saygı duyarlar.
enum Motion {
    /// Küçük geri bildirimler: hover, press, bırakma bölgesi vurgusu.
    @MainActor static var quick: Animation {
        .easeOut(duration: 0.15 * Preferences.shared.animationSpeed.factor)
    }
    /// İçerik geçişleri, liste ekle/sil, ilerleme çubukları.
    @MainActor static var standard: Animation {
        .spring(response: 0.32 * Preferences.shared.animationSpeed.factor, dampingFraction: 0.86)
    }
}

/// Ada içindeki ikon/metin butonları için ortak geri bildirim: hover'da hafif
/// büyüme, press'te küçülme + sönükleşme. Ölçek düzeni etkilemediğinden her
/// `.plain` butona güvenle uygulanabilir (layout kaymaz).
struct IslandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IslandButtonBody(configuration: configuration)
    }

    private struct IslandButtonBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.92 : (hovering ? 1.06 : 1))
                .opacity(configuration.isPressed ? 0.7 : 1)
                .onHover { hovering = $0 }
                .animation(Motion.quick, value: hovering)
                .animation(Motion.quick, value: configuration.isPressed)
        }
    }
}
