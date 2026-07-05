import AppKit

@main
struct DynamicIslandApp {
    @MainActor static var delegate: AppDelegate?

    @MainActor
    static func main() {
        // Accessory (menü çubuğu) uygulamaları, başka bir uygulama önplandayken
        // App Nap tarafından arka planda sayılıp timer'ları saniyeler mertebesinde
        // geciktirilebilir. Ada her zaman görünür bir pencereye sahip olsa da bu
        // korumayı garantiye almak için Nap'ı ve otomatik sonlandırmayı devre dışı bırak.
        ProcessInfo.processInfo.disableAutomaticTermination("Her zaman aktif menü çubuğu yardımcı uygulaması")
        ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Çentik hover algılamasının zamanında tetiklenmesini garantile"
        )

        let app = NSApplication.shared
        let appDelegate = AppDelegate()
        delegate = appDelegate
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
