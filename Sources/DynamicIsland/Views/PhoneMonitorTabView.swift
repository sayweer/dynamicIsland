import SwiftUI

/// Live monitor for a USB-connected iPhone's screen (or a Continuity Camera).
/// The capture session runs only while this tab is visible.
struct PhoneMonitorTabView: View {
    @EnvironmentObject private var phone: PhoneMonitorManager

    var body: some View {
        Group {
            if phone.authorized == false {
                monitorMessage(
                    symbol: "video.slash.fill",
                    title: "Kamera erişimi reddedildi",
                    detail: "Gizlilik ve Güvenlik → Kamera bölümünden izin verebilirsiniz",
                    actionTitle: "Sistem Ayarları'nı Aç"
                ) { SystemSettingsPane.camera.open() }
            } else if phone.devices.isEmpty {
                monitorMessage(
                    symbol: "iphone.gen3",
                    title: "iPhone bekleniyor",
                    detail: "iPhone'unuzu USB-C ile bağlayın. İlk bağlantıda telefonda "
                        + "\"Bu Bilgisayara Güven\" onayı gerekir. Telefon kilitliyse görüntü gelmeyebilir."
                )
            } else {
                preview
            }
        }
        .onAppear { phone.attachView() }
        .onDisappear { phone.detachView() }
    }

    private var preview: some View {
        CameraPreview(session: phone.session, videoGravity: .resizeAspect, mirrored: false)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .overlay(alignment: .top) { controls }
            .overlay(alignment: .bottom) { continuityFootnote }
            .overlay {
                if !phone.isRunning {
                    ProgressView().controlSize(.small)
                }
            }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if phone.devices.count > 1 {
                Menu {
                    ForEach(phone.devices) { device in
                        Button(device.name) { phone.select(device.id) }
                    }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 26, height: 24)
                .background(Circle().fill(.black.opacity(0.45)))
            }
            Spacer()
            Button {
                phone.openDetachedWindow()
            } label: {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 24)
                    .background(Circle().fill(.black.opacity(0.45)))
            }
            .buttonStyle(IslandButtonStyle())
            .help("Ayrı pencerede aç")
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(8)
    }

    @ViewBuilder
    private var continuityFootnote: some View {
        if phone.selectedKind == .continuity {
            Text("Kablosuz kaynakta iPhone Kamera uygulaması kullanılamaz.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.black.opacity(0.5)))
                .padding(8)
        }
    }

    private func monitorMessage(
        symbol: String,
        title: String,
        detail: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.3))
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .islandCard()
    }
}
