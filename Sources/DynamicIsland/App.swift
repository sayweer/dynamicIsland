import AppKit

@main
struct DynamicIslandApp {
    @MainActor static var delegate: AppDelegate?
    /// App Nap koruması yalnızca bu token yaşadığı sürece etkin kalır —
    /// saklanmazsa aktivite anında sona erer ve timer'lar arka planda
    /// (başka uygulama önplandayken) saniyeler mertebesinde geciktirilir.
    @MainActor static var appNapToken: NSObjectProtocol?

    @MainActor
    static func main() {
        ProcessInfo.processInfo.disableAutomaticTermination("Her zaman aktif menü çubuğu yardımcı uygulaması")
        // App Nap'i bastırmak için taban aktivite yeterli; timer'ın kendisi
        // .strict bayrağıyla zaten coalescing'den muaf, bu yüzden .latencyCritical
        // (Apple: "çok az uygulamanın ihtiyacı olur", sürekli açık kalması pil
        // maliyeti yaratır) bilinçli olarak kullanılmıyor.
        appNapToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Çentik hover algılaması arka planda da zamanında çalışmalı"
        )

        let app = NSApplication.shared
        let appDelegate = AppDelegate()
        delegate = appDelegate
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
