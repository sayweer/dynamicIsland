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
/// Yıkıcı toplu işlemler (rafı/panoyu temizle) için yerinde iki-adımlı onay:
/// ilk tıklama düğmeyi "Emin misiniz?" durumuna geçirir, ikinci tıklama eylemi
/// çalıştırır. Ada panelinde diyalog/sheet açmak odak çaldığı için onay yerinde
/// gösterilir; 3 sn içinde onaylanmazsa düğme eski hâline döner.
struct ConfirmingButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .white.opacity(0.5)
    let action: () -> Void

    @State private var armed = false

    var body: some View {
        Button {
            if armed {
                armed = false
                action()
            } else {
                withAnimation(Motion.quick) { armed = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(Motion.quick) { armed = false }
                }
            }
        } label: {
            Label(
                armed ? "Emin misiniz?" : title,
                systemImage: armed ? "exclamationmark.triangle.fill" : systemImage
            )
            .font(.caption2)
        }
        .buttonStyle(.plain)
        .foregroundStyle(armed ? Color.red : tint)
        .accessibilityLabel(armed ? "\(title) — onayla" : title)
    }
}

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
