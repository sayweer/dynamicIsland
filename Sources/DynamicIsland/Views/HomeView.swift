import SwiftUI
import UniformTypeIdentifiers

/// Landing tab: music player, AirDrop + shelf drop zones, app shortcuts, quick stats.
struct HomeView: View {
    var body: some View {
        HStack(spacing: 12) {
            MusicCard()
                .frame(width: 262)
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    AirDropZone()
                    ShelfDropZone()
                }
                ShortcutsRow()
                StatsRow()
            }
        }
    }
}

// MARK: - Music

struct MusicCard: View {
    @EnvironmentObject private var music: MusicManager
    @EnvironmentObject private var prefs: Preferences
    @State private var dragFraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let playing = music.nowPlaying {
                HStack(alignment: .top, spacing: 10) {
                    artworkView
                    VStack(alignment: .leading, spacing: 3) {
                        Text(playing.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text(playing.artist)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(playing.source.rawValue)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                progressBar(playing)
                controls
                if playing.isWeb && music.webJSPermissionMissing {
                    permissionHint
                }
            } else if music.automationDenied {
                // Otomasyon izni reddedilmiş: müzik çalıyor olsa bile okuyamayız.
                // "Müzik çalmıyor" demek yanıltıcı olur; kurtarma yolunu göster.
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "lock.shield")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.25))
                    Text("Otomasyon izni gerekli")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Müzik bilgisini okumak için Dynamic Island'a izin verin")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                    Button("Sistem Ayarları'nı Aç") {
                        SystemSettingsPane.automation.open()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.25))
                    Text("Müzik çalmıyor")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Apple Music veya Spotify açın")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .islandCard()
    }

    /// Web Spotify çalıyor ama tarayıcıda Apple Events JS izni kapalı: süre/seek
    /// çalışmaz. Kullanıcıya dürüstçe nedenini ve çözümü söyleriz (gizlemek yerine).
    private var permissionHint: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle")
            Text("Süre ve ileri sarma için tarayıcıda Apple Events JavaScript iznini açın")
                .lineLimit(2)
        }
        .font(.system(size: 8.5))
        .foregroundStyle(.white.opacity(0.4))
        .help("Chrome: Görünüm ▸ Geliştirici ▸ \"Apple Events'ten JavaScript'e izin ver\".\n"
            + "Safari: Geliştir ▸ \"Apple Events'ten JavaScript'e izin ver\".")
    }

    @ViewBuilder
    private var artworkView: some View {
        if let artwork = music.artwork {
            Image(nsImage: artwork)
                .resizable()
                .scaledToFill()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: 84, height: 84)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.3))
                )
        }
    }

    private func progressBar(_ playing: NowPlaying) -> some View {
        // Web Spotify'da süre yalnızca Chrome/Safari "Allow JavaScript from Apple Events" açıkken
        // okunabiliyor; duration <= 0 bunun kapalı olduğu anlamına gelir — o durumda çubuğu
        // yanıltıcı "0:00" yerine devre dışı gösteriyoruz.
        let canSeek = playing.duration > 0
        let liveFraction = dragFraction ?? (canSeek ? min(playing.position / playing.duration, 1) : 0)
        return VStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(prefs.accentColor)
                        .frame(width: geo.size.width * liveFraction)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard canSeek, geo.size.width > 0 else { return }
                            dragFraction = min(max(value.location.x / geo.size.width, 0), 1)
                        }
                        .onEnded { value in
                            guard canSeek, geo.size.width > 0 else { return }
                            music.seek(toFraction: min(max(value.location.x / geo.size.width, 0), 1))
                            dragFraction = nil
                        }
                )
            }
            .frame(height: 3)
            if canSeek {
                HStack {
                    Text(TimerCenter.format(playing.position))
                    Spacer()
                    Text(TimerCenter.format(playing.duration))
                }
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private var controls: some View {
        HStack {
            Spacer()
            Button { music.previousTrack() } label: {
                Image(systemName: "backward.fill").font(.system(size: 14))
            }
            .buttonStyle(IslandButtonStyle())
            .foregroundStyle(.white.opacity(0.8))
            .accessibilityLabel("Önceki parça")
            Button { music.playPause() } label: {
                Image(systemName: (music.nowPlaying?.isPlaying ?? false) ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30))
            }
            .buttonStyle(IslandButtonStyle())
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .accessibilityLabel((music.nowPlaying?.isPlaying ?? false) ? "Duraklat" : "Oynat")
            Button { music.nextTrack() } label: {
                Image(systemName: "forward.fill").font(.system(size: 14))
            }
            .buttonStyle(IslandButtonStyle())
            .foregroundStyle(.white.opacity(0.8))
            .accessibilityLabel("Sonraki parça")
            Spacer()
        }
    }
}

// MARK: - Drop zones

struct AirDropZone: View {
    @EnvironmentObject private var shelf: ShelfManager
    @EnvironmentObject private var prefs: Preferences
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(isTargeted ? prefs.accentColor : .white.opacity(0.7))
            Text("AirDrop")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text("Dosyayı buraya bırak")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isTargeted ? prefs.accentColor.opacity(0.18) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isTargeted ? prefs.accentColor.opacity(0.7) : Color.white.opacity(0.06),
                    style: StrokeStyle(lineWidth: 1, dash: isTargeted ? [4] : [])
                )
        )
        .animation(Motion.quick, value: isTargeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            DropUtilities.loadFileURLs(from: providers) { urls in
                shelf.airDrop(urls: urls)
            }
            return true
        }
    }
}

struct ShelfDropZone: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var shelf: ShelfManager
    @EnvironmentObject private var prefs: Preferences
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            if shelf.items.isEmpty {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isTargeted ? prefs.accentColor : .white.opacity(0.7))
                Text("Raf")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Text("Dosyaları burada beklet")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
            } else {
                HStack(spacing: -8) {
                    ForEach(shelf.items.prefix(3)) { item in
                        Image(nsImage: shelf.icon(for: item))
                            .resizable()
                            .frame(width: 30, height: 30)
                    }
                }
                Text("Raf · \(shelf.items.count) öğe")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isTargeted ? prefs.accentColor.opacity(0.15) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isTargeted ? prefs.accentColor.opacity(0.7) : Color.white.opacity(0.06),
                    style: StrokeStyle(lineWidth: 1, dash: isTargeted ? [4] : [])
                )
        )
        .animation(Motion.quick, value: isTargeted)
        .onTapGesture { vm.activeTab = .shelf }
        .onDrop(of: [UTType.fileURL, UTType.image, UTType.plainText], isTargeted: $isTargeted) { providers in
            shelf.handle(providers: providers)
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsRow: View {
    @EnvironmentObject private var shortcuts: AppShortcutsStore

    var body: some View {
        HStack(spacing: 8) {
            CardTitle("Kısayollar", symbol: "square.grid.2x2")
            Spacer()
            if shortcuts.shortcuts.isEmpty {
                Text("Eklemek için + düğmesine tıklayın")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
            }
            ForEach(shortcuts.shortcuts.suffix(7)) { shortcut in
                Button {
                    shortcuts.launch(shortcut)
                } label: {
                    Image(nsImage: shortcuts.icon(for: shortcut))
                        .resizable()
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(IslandButtonStyle())
                .help(shortcut.name)
                .accessibilityLabel("\(shortcut.name) uygulamasını aç")
                .contextMenu {
                    Button("Kaldır") { shortcuts.remove(shortcut) }
                }
            }
            Button {
                shortcuts.addViaOpenPanel()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(IslandButtonStyle())
            .help("Uygulama ekle")
            .accessibilityLabel("Uygulama ekle")
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}

// MARK: - Quick stats

struct StatsRow: View {
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var stats: SystemStats

    var body: some View {
        HStack(spacing: 12) {
            stat(symbol: "arrow.down", text: NetworkMonitor.format(network.downloadBps), tint: .green)
            stat(symbol: "arrow.up", text: NetworkMonitor.format(network.uploadBps), tint: .blue)
            Divider().frame(height: 16).overlay(Color.white.opacity(0.15))
            stat(symbol: "cpu", text: String(format: "%%%.0f", stats.cpuUsage * 100), tint: .orange)
            stat(
                symbol: "memorychip",
                text: String(format: "%.1f GB", stats.memoryUsedGB),
                tint: .purple
            )
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func stat(symbol: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}
