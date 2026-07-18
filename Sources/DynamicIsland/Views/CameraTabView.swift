import SwiftUI

/// Quick mirror using the built-in camera. Runs only while this tab is visible.
struct CameraTabView: View {
    @EnvironmentObject private var camera: CameraManager

    var body: some View {
        Group {
            if camera.authorized == false {
                cameraMessage(
                    symbol: "video.slash.fill",
                    title: "Kamera erişimi reddedildi",
                    detail: "Gizlilik ve Güvenlik → Kamera bölümünden izin verebilirsiniz",
                    actionTitle: "Sistem Ayarları'nı Aç"
                ) { SystemSettingsPane.camera.open() }
            } else if camera.unavailable {
                cameraMessage(
                    symbol: "web.camera",
                    title: "Kamera bulunamadı",
                    detail: "Bağlı bir kamera cihazı algılanamadı",
                    actionTitle: "Yeniden Dene"
                ) { camera.start() }
            } else {
                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .overlay {
                        if !camera.isRunning {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private func cameraMessage(
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
