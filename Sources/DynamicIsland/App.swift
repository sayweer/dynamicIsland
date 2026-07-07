import AppKit

@main
struct DynamicIslandApp {
    @MainActor static var delegate: AppDelegate?
    /// App Nap koruması yalnızca bu token yaşadığı sürece etkin kalır —
    /// saklanmazsa aktivite anında sona erer.
    @MainActor static var appNapToken: NSObjectProtocol?

    @MainActor
    static func main() {
        ProcessInfo.processInfo.disableAutomaticTermination("Her zaman aktif menü çubuğu yardımcı uygulaması")
        // Arka plandaki widget timer'ları (saat, pil, ağ hızı, müzik) başka
        // uygulama önplandayken de zamanında çalışsın diye App Nap'i bastırır.
        // (Hover algılama zaten event-driven global monitörle çalışıyor, Nap'ten
        // etkilenmez.) .latencyCritical bilinçli KULLANILMIYOR — Apple "çok az
        // uygulamanın ihtiyacı olur" der, sürekli açık kalması pil maliyeti yaratır.
        appNapToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Menü çubuğu widget'larının güncel kalması"
        )

        let app = NSApplication.shared
        let appDelegate = AppDelegate()
        delegate = appDelegate
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
