// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Enumera interfaces de red IPv4 activas, excluyendo loopback e interfaces
/// irrelevantes (PROJECT.md, sección 24).
struct NetworkMonitor: Sendable {
    func currentInterfaces() -> [NetworkInterface] {
        var results: [NetworkInterface] = []
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddrPointer) == 0, let firstAddr = ifaddrPointer else {
            return results
        }
        defer { freeifaddrs(ifaddrPointer) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = Self.decodeCString(interface.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }

            let ipv4 = host.withUnsafeBufferPointer { Self.decodeCString(UnsafeMutablePointer(mutating: $0.baseAddress!)) }
            results.append(NetworkInterface(id: name, displayName: name, ipv4Address: ipv4))
        }

        return results
    }

    private static func decodeCString(_ pointer: UnsafeMutablePointer<CChar>) -> String {
        let length = strlen(pointer)
        let bytes = UnsafeBufferPointer(start: pointer, count: length).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
