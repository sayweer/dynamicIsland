import Foundation
import Combine
import IOKit.ps

/// CPU, RAM and battery statistics for the system monitor widget.
@MainActor
final class SystemStats: ObservableObject {
    @Published private(set) var cpuUsage: Double = 0        // 0...1
    @Published private(set) var memoryUsage: Double = 0     // 0...1
    @Published private(set) var memoryUsedGB: Double = 0
    @Published private(set) var batteryLevel: Int?          // 0...100, nil on desktops
    @Published private(set) var batteryCharging = false

    let memoryTotalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824

    private var lastIdle: UInt64 = 0
    private var lastTotal: UInt64 = 0
    private var timer: Timer?
    private var batteryTick = 0

    init() {
        (lastIdle, lastTotal) = Self.cpuTicks()
        refreshBattery()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        let (idle, total) = Self.cpuTicks()
        let idleDelta = Double(idle >= lastIdle ? idle - lastIdle : 0)
        let totalDelta = Double(total >= lastTotal ? total - lastTotal : 0)
        if totalDelta > 0 {
            cpuUsage = min(max(1.0 - idleDelta / totalDelta, 0), 1)
        }
        lastIdle = idle
        lastTotal = total

        if let used = Self.usedMemoryBytes() {
            memoryUsedGB = Double(used) / 1_073_741_824
            memoryUsage = min(memoryUsedGB / max(memoryTotalGB, 0.1), 1)
        }

        batteryTick += 1
        if batteryTick % 15 == 0 { refreshBattery() }
    }

    private func refreshBattery() {
        if let info = Self.battery() {
            batteryLevel = info.level
            batteryCharging = info.charging
        } else {
            batteryLevel = nil
        }
    }

    // MARK: - Low-level readers

    nonisolated private static func cpuTicks() -> (idle: UInt64, total: UInt64) {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        return (idle, user + system + idle + nice)
    }

    nonisolated private static func usedMemoryBytes() -> UInt64? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let used = UInt64(stats.active_count)
            &+ UInt64(stats.wire_count)
            &+ UInt64(stats.compressor_page_count)
        return used &* UInt64(pageSize)
    }

    nonisolated private static func battery() -> (level: Int, charging: Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if let capacity = description[kIOPSCurrentCapacityKey as String] as? Int,
               let max = description[kIOPSMaxCapacityKey as String] as? Int, max > 0 {
                let charging = (description[kIOPSIsChargingKey as String] as? Bool) ?? false
                return (Int(Double(capacity) / Double(max) * 100), charging)
            }
        }
        return nil
    }
}
