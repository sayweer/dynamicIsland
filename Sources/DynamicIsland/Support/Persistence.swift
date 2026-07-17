import Foundation
import os

enum Persistence {
    private static let log = Logger(subsystem: "com.opensource.DynamicIsland", category: "Persistence")

    static let appSupportURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("DynamicIsland", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            log.error("App Support dizini oluşturulamadı: \(error.localizedDescription, privacy: .public)")
        }
        return dir
    }()

    static func directory(_ name: String) -> URL {
        let dir = appSupportURL.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            log.error("\(name, privacy: .public) dizini oluşturulamadı: \(error.localizedDescription, privacy: .public)")
        }
        return dir
    }

    static func load<T: Decodable>(_ type: T.Type, from fileName: String) -> T? {
        let url = appSupportURL.appendingPathComponent(fileName)
        // İlk açılışta dosya henüz yok — bu normal, sessizce nil dön.
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // Geçici okuma hatası (başka süreç tutuyor vb.): dosya sağlam olabilir,
            // karantinaya ALMA — aksi halde sağlam veriyi kaybederiz.
            log.error("\(fileName, privacy: .public) okunamadı (geçici): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Decode hatası: veri gerçekten bozuk/uyumsuz. Yana taşıyoruz ki bir sonraki
            // save üzerine yazıp veriyi kalıcı silmesin, kurtarma şansı kalsın.
            log.error("\(fileName, privacy: .public) çözümlenemedi, karantinaya alınıyor: \(error.localizedDescription, privacy: .public)")
            quarantine(url)
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, to fileName: String) {
        let url = appSupportURL.appendingPathComponent(fileName)
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            log.error("\(fileName, privacy: .public) yazılamadı: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Bozuk dosyayı `<isim>.corrupt` olarak yana taşır. İlk kurtarma kopyasını korur:
    /// zaten bir `.corrupt` varsa üzerine yazmaz (o, gerçek veriyi taşıyan kopya olabilir;
    /// yeni bozuk dosya nasılsa çözümlenemiyor, bir sonraki save onu geçersiz kılabilir).
    private static func quarantine(_ url: URL) {
        let backup = url.appendingPathExtension("corrupt")
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        try? FileManager.default.moveItem(at: url, to: backup)
    }
}
