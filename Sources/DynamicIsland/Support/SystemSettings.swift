import AppKit

/// Sistem Ayarları'nın Gizlilik ve Güvenlik bölmelerine derin bağlantı.
/// İzin reddedildiğinde kullanıcıyı yolu tarif etmek yerine doğrudan götürür.
enum SystemSettingsPane: String {
    case automation = "Privacy_Automation"
    case camera = "Privacy_Camera"
    case calendars = "Privacy_Calendars"

    func open() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
