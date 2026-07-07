import AppKit
import Combine

struct NowPlaying: Equatable {
    enum Source: String {
        case appleMusic = "Apple Music"
        case spotify = "Spotify"
    }

    var source: Source
    var title: String
    var artist: String
    var isPlaying: Bool
    var duration: Double
    var position: Double
    /// Tarayıcıdaki (Chrome/Safari) Spotify web player'dan geliyorsa true —
    /// native uygulama olmadığı için AppleScript kontrolleri (playpause vb.) uygulanmaz.
    var isWeb = false

    var trackKey: String { "\(source.rawValue)|\(title)|\(artist)" }
}

/// Now-playing info + controls for Apple Music and Spotify via Apple Events.
/// Only talks to apps that are already running so it never launches them.
@MainActor
final class MusicManager: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var artwork: NSImage?

    private var timer: Timer?
    private var lastArtworkKey = ""
    private let scriptQueue = DispatchQueue(label: "dynamicisland.music", qos: .utility)

    private static let spotifyBundleID = "com.spotify.client"
    private static let musicBundleID = "com.apple.Music"
    private static let chromeBundleID = "com.google.Chrome"
    private static let safariBundleID = "com.apple.Safari"

    init() {
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private func poll() {
        let spotifyRunning = Self.isRunning(Self.spotifyBundleID)
        let musicRunning = Self.isRunning(Self.musicBundleID)
        // Web/PWA Spotify: native Spotify yokken tarayıcıdaki sekmeyi tara.
        let chromeRunning = !spotifyRunning && Self.isRunning(Self.chromeBundleID)
        let safariRunning = !spotifyRunning && Self.isRunning(Self.safariBundleID)
        guard spotifyRunning || musicRunning || chromeRunning || safariRunning else {
            if nowPlaying != nil {
                nowPlaying = nil
                artwork = nil
                lastArtworkKey = ""
            }
            return
        }

        scriptQueue.async { [weak self] in
            var spotify: NowPlaying?
            var music: NowPlaying?
            var spotifyArtURL: String?

            if spotifyRunning {
                let result = Self.runScript(
                    """
                    tell application "Spotify"
                        if player state is stopped then return "stopped"
                        set t to current track
                        return (player state as string) & "|~|" & (name of t) & "|~|" & (artist of t) & "|~|" & ((duration of t) / 1000) & "|~|" & player position & "|~|" & (artwork url of t)
                    end tell
                    """
                )
                if let parts = Self.split(result), parts.count >= 6 {
                    spotify = NowPlaying(
                        source: .spotify,
                        title: parts[1],
                        artist: parts[2],
                        isPlaying: parts[0] == "playing",
                        duration: Double(parts[3]) ?? 0,
                        position: Double(parts[4]) ?? 0
                    )
                    spotifyArtURL = parts[5]
                }
            }
            if musicRunning {
                let result = Self.runScript(
                    """
                    tell application "Music"
                        if player state is stopped then return "stopped"
                        try
                            set t to current track
                            return (player state as string) & "|~|" & (name of t) & "|~|" & (artist of t) & "|~|" & (duration of t) & "|~|" & player position & "|~|" & ""
                        on error
                            return "stopped"
                        end try
                    end tell
                    """
                )
                if let parts = Self.split(result), parts.count >= 5 {
                    music = NowPlaying(
                        source: .appleMusic,
                        title: parts[1],
                        artist: parts[2],
                        isPlaying: parts[0] == "playing",
                        duration: Double(parts[3]) ?? 0,
                        position: Double(parts[4]) ?? 0
                    )
                }
            }

            // Native Spotify yoksa tarayıcıdaki web Spotify'ı dene.
            var web: NowPlaying?
            if spotify == nil, chromeRunning || safariRunning {
                web = Self.webSpotify(chrome: chromeRunning, safari: safariRunning)
            }

            // Prefer whichever player is actively playing; otherwise show any paused track.
            let candidates = [spotify, music, web].compactMap { $0 }
            let chosen = candidates.first(where: { $0.isPlaying }) ?? candidates.first

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.nowPlaying = chosen
                self.refreshArtworkIfNeeded(for: chosen, spotifyArtURL: spotifyArtURL)
            }
        }
    }

    // MARK: - Web (tarayıcı) Spotify

    /// Chrome/Safari'de açık `open.spotify.com` sekmesinin başlığından çalan parçayı
    /// çıkarır. Spotify web player başlığı çalarken "Şarkı • Sanatçı", duraklatınca
    /// yalnızca "Spotify" olur; ayraç (•) yoksa çalmıyor sayılır.
    nonisolated private static func webSpotify(chrome: Bool, safari: Bool) -> NowPlaying? {
        var browsers: [(app: String, titleProperty: String)] = []
        if chrome { browsers.append(("Google Chrome", "title")) }
        if safari { browsers.append(("Safari", "name")) }
        for (app, titleProperty) in browsers {
            let script = """
            tell application "\(app)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t) contains "open.spotify.com" then return (\(titleProperty) of t)
                    end repeat
                end repeat
            end tell
            return ""
            """
            guard let title = runScript(script)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { continue }
            if let playing = parseSpotifyWebTitle(title) { return playing }
        }
        return nil
    }

    nonisolated private static func parseSpotifyWebTitle(_ title: String) -> NowPlaying? {
        // Ayraç bullet (U+2022) etrafında boşluklu. Yoksa (yalnızca "Spotify") çalmıyor.
        let separator = " • "
        guard title.contains(separator) else { return nil }
        let parts = title.components(separatedBy: separator)
        let track = parts[0].trimmingCharacters(in: .whitespaces)
        let artist = parts.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespaces)
        guard !track.isEmpty else { return nil }
        return NowPlaying(
            source: .spotify, title: track, artist: artist,
            isPlaying: true, duration: 0, position: 0, isWeb: true
        )
    }

    private func refreshArtworkIfNeeded(for playing: NowPlaying?, spotifyArtURL: String?) {
        guard let playing else {
            artwork = nil
            lastArtworkKey = ""
            return
        }
        guard playing.trackKey != lastArtworkKey else { return }
        lastArtworkKey = playing.trackKey

        // Web player'dan kapak resmi alınamaz; eski kapağı temizle.
        if playing.isWeb {
            artwork = nil
            return
        }

        switch playing.source {
        case .spotify:
            guard let raw = spotifyArtURL, let url = URL(string: raw) else { return }
            let key = playing.trackKey
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = NSImage(data: data) else { return }
                Task { @MainActor in
                    guard let self, self.lastArtworkKey == key else { return }
                    self.artwork = image
                }
            }.resume()
        case .appleMusic:
            let key = playing.trackKey
            scriptQueue.async { [weak self] in
                let descriptor = Self.runScriptDescriptor(
                    """
                    tell application "Music"
                        try
                            return data of artwork 1 of current track
                        on error
                            return ""
                        end try
                    end tell
                    """
                )
                guard let data = descriptor?.data, data.count > 32,
                      let image = NSImage(data: data) else {
                    Task { @MainActor in
                        guard let self, self.lastArtworkKey == key else { return }
                        self.artwork = nil
                    }
                    return
                }
                Task { @MainActor in
                    guard let self, self.lastArtworkKey == key else { return }
                    self.artwork = image
                }
            }
        }
    }

    // MARK: - Controls

    func playPause() { control("playpause") }
    func nextTrack() { control("next track") }
    func previousTrack() { control("previous track") }

    /// Web player'da native uygulama olmadığından kontrol/seek uygulanamaz.
    var canControl: Bool { nowPlaying?.isWeb == false }

    func seek(to position: Double) {
        guard let playing = nowPlaying, !playing.isWeb else { return }
        let app = playing.source == .spotify ? "Spotify" : "Music"
        scriptQueue.async {
            _ = Self.runScript("tell application \"\(app)\" to set player position to \(Int(position))")
        }
        nowPlaying?.position = position
    }

    private func control(_ command: String) {
        guard let playing = nowPlaying, !playing.isWeb else { return }
        let app = playing.source == .spotify ? "Spotify" : "Music"
        scriptQueue.async { [weak self] in
            _ = Self.runScript("tell application \"\(app)\" to \(command)")
            Task { @MainActor in self?.poll() }
        }
    }

    // MARK: - AppleScript helpers

    nonisolated private static func split(_ result: String?) -> [String]? {
        guard let result, result != "stopped", !result.isEmpty else { return nil }
        return result.components(separatedBy: "|~|")
    }

    nonisolated private static func runScript(_ source: String) -> String? {
        runScriptDescriptor(source)?.stringValue
    }

    nonisolated private static func runScriptDescriptor(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return descriptor
    }
}
