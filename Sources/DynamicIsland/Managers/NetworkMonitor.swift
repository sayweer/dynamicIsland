import Foundation
import Combine

/// Real-time up/down throughput sampled from interface byte counters.
@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var downloadBps: Double = 0
    @Published private(set) var uploadBps: Double = 0
    /// Rolling download samples for the mini graph (most recent last).
    @Published private(set) var history: [Double] = []

    private var lastRx: UInt64 = 0
    private var lastTx: UInt64 = 0
    private var lastSample = Date()
    private var timer: Timer?

    init() {
        (lastRx, lastTx) = Self.counters()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        let (rx, tx) = Self.counters()
        let elapsed = max(Date().timeIntervalSince(lastSample), 0.1)
        // Counters are 32-bit and wrap; ignore negative deltas.
        let rxDelta = rx >= lastRx ? rx - lastRx : 0
        let txDelta = tx >= lastTx ? tx - lastTx : 0
        downloadBps = Double(rxDelta) / elapsed
        uploadBps = Double(txDelta) / elapsed
        lastRx = rx
        lastTx = tx
        lastSample = Date()

        history.append(downloadBps)
        if history.count > 30 { history.removeFirst() }
    }

    nonisolated private static func counters() -> (UInt64, UInt64) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return (0, 0) }
        defer { freeifaddrs(addrs) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var pointer = addrs
        while let current = pointer {
            let ifa = current.pointee
            if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK),
               let dataPointer = ifa.ifa_data {
                let name = String(cString: ifa.ifa_name)
                if name.hasPrefix("en") {
                    let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
                    rx &+= UInt64(data.ifi_ibytes)
                    tx &+= UInt64(data.ifi_obytes)
                }
            }
            pointer = ifa.ifa_next
        }
        return (rx, tx)
    }

    static func format(_ bps: Double) -> String {
        switch bps {
        case ..<1024: return String(format: "%.0f B/s", bps)
        case ..<(1024 * 1024): return String(format: "%.0f KB/s", bps / 1024)
        default: return String(format: "%.1f MB/s", bps / 1024 / 1024)
        }
    }
}
