// LAN Scanner — NetworkInterfaceManager.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import Foundation
import Darwin

/// Enumerates active IPv4 network interfaces on the local machine.
///
/// Uses the POSIX `getifaddrs` system call to iterate over all interfaces,
/// filters out the loopback interface (`lo0`) and any interface that is not
/// currently up, then converts the raw socket address data to `NetworkInterface` values.
final class NetworkInterfaceManager: Sendable {
    /// Returns all active, non-loopback IPv4 network interfaces.
    ///
    /// - Returns: An array of `NetworkInterface` values ready to display in the UI.
    static func getActiveInterfaces() -> [NetworkInterface] {
        var interfaces: [NetworkInterface] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr = Optional(firstAddr)
        while let current = ptr {
            let addr = current.pointee
            let family = addr.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                let name = String(cString: addr.ifa_name)
                guard name != "lo0" else { ptr = addr.ifa_next; continue }
                guard addr.ifa_flags & UInt32(IFF_UP) != 0 else { ptr = addr.ifa_next; continue }

                var ip = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var mask = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))

                addr.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sinPtr in
                    var sin = sinPtr.pointee
                    inet_ntop(AF_INET, &sin.sin_addr, &ip, socklen_t(INET_ADDRSTRLEN))
                }

                if let maskAddr = addr.ifa_netmask {
                    maskAddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { msinPtr in
                        var msin = msinPtr.pointee
                        inet_ntop(AF_INET, &msin.sin_addr, &mask, socklen_t(INET_ADDRSTRLEN))
                    }
                }

                let ipStr = String(cString: ip)
                let maskStr = String(cString: mask)
                let cidr = NetworkInterfaceManager.computeCIDR(ip: ipStr, mask: maskStr)

                let iface = NetworkInterface(
                    id: name,
                    displayName: NetworkInterfaceManager.interfaceDisplayName(name),
                    ipAddress: ipStr,
                    subnetMask: maskStr,
                    cidr: cidr,
                    isWifi: name.hasPrefix("en")
                )
                interfaces.append(iface)
            }
            ptr = addr.ifa_next
        }
        return interfaces
    }

    /// Derives the CIDR network address for an interface from its IP address and subnet mask.
    ///
    /// Example: IP `192.168.1.42`, mask `255.255.255.0` → `"192.168.1.0/24"`.
    ///
    /// - Parameters:
    ///   - ip: The IPv4 address string.
    ///   - mask: The subnet mask in dotted-decimal notation.
    /// - Returns: A CIDR string such as `"192.168.1.0/24"`, or `"<ip>/24"` on parse failure.
    static func computeCIDR(ip: String, mask: String) -> String {
        let ipParts = ip.split(separator: ".").compactMap { UInt32($0) }
        let maskParts = mask.split(separator: ".").compactMap { UInt32($0) }
        guard ipParts.count == 4, maskParts.count == 4 else { return "\(ip)/24" }

        let prefixLen = maskParts.reduce(0) { $0 + $1.nonzeroBitCount }
        var netParts = [UInt32]()
        for i in 0..<4 {
            netParts.append(ipParts[i] & maskParts[i])
        }
        let networkAddr = netParts.map { String($0) }.joined(separator: ".")
        return "\(networkAddr)/\(prefixLen)"
    }

    /// Returns a human-readable display name for a BSD interface name.
    ///
    /// - `en0`  → `"Wi-Fi (en0)"`
    /// - `en1`… → `"Ethernet (en1)…"`
    /// - `utun*`→ `"VPN (utun*)"`
    /// - others → the raw BSD name unchanged
    static func interfaceDisplayName(_ name: String) -> String {
        if name == "en0" { return "Wi-Fi (en0)" }
        if name.hasPrefix("en") { return "Ethernet (\(name))" }
        if name.hasPrefix("utun") { return "VPN (\(name))" }
        return name
    }
}
