import Foundation
import Combine

/// Real-time up/down throughput sampled from interface byte counters.
@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var downloadBps: Double = 0
    @Published private(set) var uploadBps: Double = 0
    /// Rolling download samples for the mini graph (most recent last).
    @Published private(set) var history: [Double] = []

    private var lastCounters: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var lastSample = Date()
    private var timer: Timer?
    private var isActive = true

    init() {
        lastCounters = Self.counters()
        startTimer()
    }

    deinit { timer?.invalidate() }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Ağ hızı yalnızca görünürken (genişlemiş panel veya kapalı sağ modül "ağ"
    /// iken) örneklenir; aksi halde timer durur. Boşta CPU'yu düşürür.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            // Duraklamadan sonra sahte dev artış görünmesin diye baseline'ı sıfırla.
            lastCounters = Self.counters()
            lastSample = Date()
            startTimer()
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func sample() {
        let current = Self.counters()
        let elapsed = max(Date().timeIntervalSince(lastSample), 0.1)
        // Arayüz başına delta. Sayaç azaldıysa (32-bit sarma VEYA arayüz sıfırlanması
        // — uyku/uyanma, sürücü reload) o arayüzün bu tur katkısını 0 say; sıfırlanmayı
        // sahte ~4GB sıçrama olarak göstermeyiz. Yeni beliren arayüz bir tur atlanır.
        var rxDelta: UInt64 = 0
        var txDelta: UInt64 = 0
        for (name, c) in current {
            guard let last = lastCounters[name] else { continue }
            if c.rx >= last.rx { rxDelta += UInt64(c.rx - last.rx) }
            if c.tx >= last.tx { txDelta += UInt64(c.tx - last.tx) }
        }
        lastCounters = current
        downloadBps = Double(rxDelta) / elapsed
        uploadBps = Double(txDelta) / elapsed
        lastSample = Date()

        history.append(downloadBps)
        if history.count > 30 { history.removeFirst() }
    }

    /// Aktif (IFF_UP + IFF_RUNNING) `en*` arayüzlerinin bayt sayaçları — arayüz başına.
    /// Sanal/kapalı arayüzler (bridge, kapalı VPN) hariç tutulur.
    nonisolated private static func counters() -> [String: (rx: UInt32, tx: UInt32)] {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return [:] }
        defer { freeifaddrs(addrs) }

        let up = UInt32(IFF_UP), running = UInt32(IFF_RUNNING)
        var result: [String: (rx: UInt32, tx: UInt32)] = [:]
        var pointer = addrs
        while let current = pointer {
            let ifa = current.pointee
            if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK),
               let dataPointer = ifa.ifa_data,
               (ifa.ifa_flags & up) != 0, (ifa.ifa_flags & running) != 0 {
                let name = String(cString: ifa.ifa_name)
                if name.hasPrefix("en") {
                    let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
                    result[name] = (data.ifi_ibytes, data.ifi_obytes)
                }
            }
            pointer = ifa.ifa_next
        }
        return result
    }

    static func format(_ bps: Double) -> String {
        switch bps {
        case ..<1024: return String(format: "%.0f B/s", bps)
        case ..<(1024 * 1024): return String(format: "%.0f KB/s", bps / 1024)
        default: return String(format: "%.1f MB/s", bps / 1024 / 1024)
        }
    }
}
