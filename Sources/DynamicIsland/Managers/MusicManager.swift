import AppKit
import Combine
import CoreGraphics

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

    nonisolated private static let spotifyBundleID = "com.spotify.client"
    nonisolated private static let musicBundleID = "com.apple.Music"
    nonisolated private static let chromeBundleID = "com.google.Chrome"
    nonisolated private static let safariBundleID = "com.apple.Safari"

    init() {
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    nonisolated private static func isRunning(_ bundleID: String) -> Bool {
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
                if var w = web {
                    // Chrome/Safari'de "Allow JavaScript from Apple Events" açıksa gerçek
                    // pozisyon/süre okunabilir; kapalıysa sessizce 0/0 kalır (bkz. seek/control).
                    if let raw = Self.runBrowserJS(Self.playbackTimeJS),
                       let sep = raw.range(of: "|~|") {
                        w.position = Self.parseTimecode(String(raw[raw.startIndex..<sep.lowerBound])) ?? 0
                        w.duration = Self.parseTimecode(String(raw[sep.upperBound...])) ?? 0
                    }
                    web = w
                }
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

    private enum Playback {
        case playPause, next, previous

        var appleScriptCommand: String {
            switch self {
            case .playPause: return "playpause"
            case .next: return "next track"
            case .previous: return "previous track"
            }
        }
        /// Spotify web player'daki kontrol düğmesinin data-testid'si.
        var webTestID: String {
            switch self {
            case .playPause: return "control-button-playpause"
            case .next: return "control-button-skip-forward"
            case .previous: return "control-button-skip-back"
            }
        }
        /// NX_KEYTYPE_PLAY / NEXT / PREVIOUS — donanım medya tuşlarının ürettiği aynı sistem olayı.
        var mediaKey: Int32 {
            switch self {
            case .playPause: return 16
            case .next: return 17
            case .previous: return 18
            }
        }
    }

    func playPause() { control(.playPause) }
    func nextTrack() { control(.next) }
    func previousTrack() { control(.previous) }

    /// `fraction`: 0...1 — parça süresi boyunca oran. Native oynatıcıda gerçek saniyeye,
    /// web'de ilerleme çubuğu üzerinde bir tıklamayı simüle etmek için kullanılır.
    func seek(toFraction fraction: Double) {
        guard let playing = nowPlaying else { return }
        let clamped = min(max(fraction, 0), 1)
        if playing.isWeb {
            scriptQueue.async { _ = Self.runBrowserJS(Self.seekJS(fraction: clamped)) }
        } else {
            let app = playing.source == .spotify ? "Spotify" : "Music"
            let position = Int(clamped * playing.duration)
            scriptQueue.async {
                _ = Self.runScript("tell application \"\(app)\" to set player position to \(position)")
            }
        }
        nowPlaying?.position = clamped * playing.duration
    }

    private func control(_ playback: Playback) {
        guard let playing = nowPlaying else { return }
        if playing.isWeb {
            scriptQueue.async { [weak self] in
                // Önce web player'ın kendi düğmesine tıklamayı dene (JS Apple Events'ten kapalıysa
                // nil döner); olmazsa donanım medya tuşunu simüle et — ikisi de aynı sonucu verir.
                if Self.runBrowserJS(Self.clickJS(testID: playback.webTestID)) == nil {
                    Self.postMediaKey(playback.mediaKey)
                }
                Task { @MainActor in self?.poll() }
            }
            return
        }
        let app = playing.source == .spotify ? "Spotify" : "Music"
        scriptQueue.async { [weak self] in
            _ = Self.runScript("tell application \"\(app)\" to \(playback.appleScriptCommand)")
            Task { @MainActor in self?.poll() }
        }
    }

    /// Donanım medya tuşuyla aynı sistem olayını (NX_KEYTYPE_*) üretir; hangi uygulamanın
    /// bunu aldığını macOS kendi "now playing" sahibine göre belirler (fiziksel tuşla aynı davranış).
    nonisolated private static func postMediaKey(_ key: Int32) {
        for keyDown in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: keyDown ? 0xa00 : 0xb00)
            let data1 = (Int(key) << 16) | ((keyDown ? 0xa : 0xb) << 8)
            guard let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: Int16(8), data1: data1, data2: -1
            ), let cgEvent = event.cgEvent else { continue }
            cgEvent.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }

    // MARK: - Web (tarayıcı) JavaScript köprüsü

    /// Chrome/Safari'de açık open.spotify.com sekmesinde JS çalıştırır. Bunun için tarayıcıda
    /// "View > Developer > Allow JavaScript from Apple Events" açık olmalı; kapalıysa (veya
    /// sekme yoksa) nil döner — çağıran taraf bunu "web JS kullanılamıyor" olarak ele alır.
    nonisolated private static func runBrowserJS(_ js: String) -> String? {
        let script = escapeForAppleScript(js)
        if isRunning(chromeBundleID),
           let result = runScript(chromeJSScript(script)), result != "no-tab" {
            return result
        }
        if isRunning(safariBundleID),
           let result = runScript(safariJSScript(script)), result != "no-tab" {
            return result
        }
        return nil
    }

    nonisolated private static func escapeForAppleScript(_ js: String) -> String {
        js.replacingOccurrences(of: "\"", with: "\\\"")
    }

    nonisolated private static func chromeJSScript(_ escapedJS: String) -> String {
        """
        tell application "Google Chrome"
            repeat with w in windows
                repeat with t in tabs of w
                    if (URL of t) contains "open.spotify.com" then
                        return execute t javascript "\(escapedJS)"
                    end if
                end repeat
            end repeat
        end tell
        return "no-tab"
        """
    }

    nonisolated private static func safariJSScript(_ escapedJS: String) -> String {
        """
        tell application "Safari"
            repeat with w in windows
                repeat with t in tabs of w
                    if (URL of t) contains "open.spotify.com" then
                        return do JavaScript "\(escapedJS)" in t
                    end if
                end repeat
            end repeat
        end tell
        return "no-tab"
        """
    }

    nonisolated private static func clickJS(testID: String) -> String {
        "(function(){var b=document.querySelector('[data-testid=\"\(testID)\"]');" +
        "if(b){b.click();return 'ok';}return 'missing';})()"
    }

    /// "pozisyon|~|süre" (ör. "1:23|~|3:45") döndürür.
    nonisolated private static var playbackTimeJS: String {
        "(function(){var p=document.querySelector('[data-testid=\"playback-position\"]');" +
        "var d=document.querySelector('[data-testid=\"playback-duration\"]');" +
        "return (p?p.textContent:'')+'|~|'+(d?d.textContent:'');})()"
    }

    /// İlerleme çubuğunun `fraction` (0...1) noktasında gerçek bir tıklamayı simüle eder —
    /// Spotify'ın ilerleme çubuğu native bir <input> değil, sürüklenebilir bir div olduğundan.
    nonisolated private static func seekJS(fraction: Double) -> String {
        "(function(){var bg=document.querySelector('[data-testid=\"progress-bar-background\"]');" +
        "if(!bg)return 'missing';var r=bg.getBoundingClientRect();" +
        "var x=r.left+r.width*\(fraction);var y=r.top+r.height/2;" +
        "var o={bubbles:true,cancelable:true,clientX:x,clientY:y,button:0};" +
        "bg.dispatchEvent(new PointerEvent('pointerdown',o));" +
        "bg.dispatchEvent(new MouseEvent('mousedown',o));" +
        "window.dispatchEvent(new PointerEvent('pointermove',o));" +
        "window.dispatchEvent(new MouseEvent('mousemove',o));" +
        "window.dispatchEvent(new PointerEvent('pointerup',o));" +
        "window.dispatchEvent(new MouseEvent('mouseup',o));" +
        "bg.dispatchEvent(new MouseEvent('click',o));return 'ok';})()"
    }

    /// "1:23" veya "1:02:03" biçimindeki metni saniyeye çevirir.
    nonisolated private static func parseTimecode(_ text: String) -> Double? {
        let rawParts = text.trimmingCharacters(in: .whitespaces).components(separatedBy: ":")
        let parts = rawParts.compactMap { Int($0) }
        guard !parts.isEmpty, parts.count == rawParts.count else { return nil }
        return parts.reversed().enumerated().reduce(0.0) { total, item in
            total + Double(item.element) * pow(60, Double(item.offset))
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
