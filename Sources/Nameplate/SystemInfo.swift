import Darwin
import Foundation

/// Cheap one-shot samples for the status menu and name-tag info lines.
/// Everything here is a fast syscall — safe to call on the main thread.
enum SystemInfo {
    static func uptimeSeconds() -> Int? {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boottime, &size, nil, 0) == 0,
              boottime.tv_sec > 0 else { return nil }
        let seconds = Int(Date().timeIntervalSince1970) - Int(boottime.tv_sec)
        return seconds > 0 ? seconds : nil
    }

    static func uptime() -> String? {
        guard let seconds = self.uptimeSeconds() else { return nil }
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    struct IPAddressCandidate {
        var address: String
        var interface: String
        var family: Int32
        var ipv6Bytes: [UInt8] = []
    }

    /// First non-loopback IP address, preferring IPv4 and wired/Wi-Fi (enX)
    /// interfaces over VPN/tunnel interfaces so the LAN address wins.
    static func primaryIPAddress() -> (address: String, interface: String)? {
        var ipv4: [IPAddressCandidate] = []
        var ipv6: [IPAddressCandidate] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0 else { return nil }
        defer { freeifaddrs(pointer) }

        var current = pointer
        while let ifa = current {
            defer { current = ifa.pointee.ifa_next }
            guard let addr = ifa.pointee.ifa_addr,
                  (addr.pointee.sa_family == UInt8(AF_INET) || addr.pointee.sa_family == UInt8(AF_INET6)),
                  (ifa.pointee.ifa_flags & UInt32(IFF_UP)) != 0,
                  (ifa.pointee.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            let interface = self.string(from: ifa.pointee.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                addr, socklen_t(addr.pointee.sa_len),
                &host, socklen_t(host.count),
                nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let address = host.withUnsafeBufferPointer { self.string(from: $0.baseAddress!) }
            if addr.pointee.sa_family == UInt8(AF_INET) {
                ipv4.append(IPAddressCandidate(address: address, interface: interface, family: AF_INET))
            } else {
                let bytes = self.ipv6Bytes(from: addr)
                guard self.isUsableIPv6(bytes) else { continue }
                ipv6.append(IPAddressCandidate(
                    address: address,
                    interface: interface,
                    family: AF_INET6,
                    ipv6Bytes: bytes))
            }
        }

        return self.primaryIPAddress(from: ipv4 + ipv6)
    }

    static func primaryIPAddress(from addresses: [IPAddressCandidate]) -> (address: String, interface: String)? {
        let ipv4 = addresses.filter { $0.family == AF_INET }
        let ipv6 = addresses.filter { $0.family == AF_INET6 && self.isUsableIPv6($0.ipv6Bytes) }
        return self.ranked(ipv4).first.map { ($0.address, $0.interface) }
            ?? self.ranked(ipv6).first.map { ($0.address, $0.interface) }
    }

    static func ranked(_ addresses: [IPAddressCandidate]) -> [IPAddressCandidate] {
        addresses.sorted { lhs, rhs in
            func rank(_ name: String) -> Int {
                name.hasPrefix("en") ? 0 : 1
            }
            if rank(lhs.interface) != rank(rhs.interface) {
                return rank(lhs.interface) < rank(rhs.interface)
            }
            return lhs.interface < rhs.interface
        }
    }

    static func isUsableIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        if bytes.allSatisfy({ $0 == 0 }) { return false } // ::
        if bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1 { return false } // ::1
        if bytes[0] == 0xFF { return false } // multicast
        if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 { return false } // fe80::/10 link-local
        if (bytes[0] & 0xFE) == 0xFC { return false } // fc00::/7 unique-local
        return true
    }

    private static func ipv6Bytes(from pointer: UnsafePointer<sockaddr>) -> [UInt8] {
        pointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { address in
            withUnsafeBytes(of: address.pointee.sin6_addr) { Array($0) }
        }
    }

    static func loadAverage() -> Double? {
        var load = [Double](repeating: 0, count: 3)
        guard getloadavg(&load, 3) >= 1 else { return nil }
        return load[0]
    }

    static func memory() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(sysconf(_SC_PAGESIZE))
        let used = (UInt64(stats.active_count)
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)) * pageSize
        return (used, ProcessInfo.processInfo.physicalMemory)
    }

    private static func string(from pointer: UnsafePointer<CChar>) -> String {
        String(decoding: UnsafeRawBufferPointer(start: pointer, count: strlen(pointer)), as: UTF8.self)
    }

    static func diskFree() -> Int64? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]) else { return nil }
        return values.volumeAvailableCapacityForImportantUsage
    }

    static func statsLine() -> String {
        var parts: [String] = []
        if let load = loadAverage() {
            let cores = ProcessInfo.processInfo.activeProcessorCount
            parts.append(String(format: "CPU %.1f load · %d cores", load, cores))
        }
        if let memory = memory() {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .memory
            formatter.allowedUnits = .useGB
            let used = formatter.string(fromByteCount: Int64(memory.used))
            let total = formatter.string(fromByteCount: Int64(memory.total))
            parts.append("RAM \(used) of \(total)")
        }
        return parts.joined(separator: "  ·  ")
    }

    static func diskLine() -> String? {
        guard let free = diskFree() else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "Disk \(formatter.string(fromByteCount: free)) free"
    }
}
