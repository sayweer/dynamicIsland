import SwiftUI

/// Quick mirror using the built-in camera. Runs only while this tab is visible.
struct CameraTabView: View {
    @EnvironmentObject private var camera: CameraManager

    var body: some View {
        Group {
            if camera.authorized == false {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Kamera erişimi reddedildi")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Sistem Ayarları → Gizlilik ve Güvenlik → Kamera bölümünden izin verebilirsiniz")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .islandCard()
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
}
