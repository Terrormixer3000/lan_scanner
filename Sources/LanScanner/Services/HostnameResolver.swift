// LAN Scanner — HostnameResolver.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import Foundation
import Darwin

/// Resolves IPv4 addresses to human-readable hostnames via DNS reverse lookups.
///
/// The resolver first tries the Cocoa `Host` API (which can leverage the system DNS cache
/// and mDNS simultaneously), then falls back to the POSIX `getnameinfo` syscall.
/// Results are categorised into plain DNS names and `.local` mDNS names.
enum HostnameResolver {
    /// The combined result of resolving a single IP address.
    struct Resolution: Sendable {
        /// The preferred resolved hostname — mDNS name if available, otherwise the DNS name.
        let hostname: String?
        /// The fully-qualified DNS name, or `nil` if no DNS entry was found.
        let dnsName: String?
        /// The Bonjour / mDNS `.local` name, or `nil` if the host does not advertise one.
        let mdnsName: String?
    }

    /// Resolves a single IPv4 address to its hostname.
    ///
    /// - Parameter ip: The IPv4 address to look up.
    /// - Returns: A `Resolution` with whatever DNS/mDNS names could be obtained.
    static func resolve(ip: String) async -> Resolution {
        if let hostName = resolveViaHost(ip: ip) {
            return splitResolvedName(hostName, ip: ip)
        }

        return await withCheckedContinuation { continuation in
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            inet_pton(AF_INET, ip, &addr.sin_addr)

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = withUnsafePointer(to: addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    getnameinfo(
                        sockPtr,
                        socklen_t(MemoryLayout<sockaddr_in>.size),
                        &hostname,
                        socklen_t(NI_MAXHOST),
                        nil, 0,
                        NI_NAMEREQD
                    )
                }
            }

            if result == 0 {
                let resolvedName = normalize(String(cString: hostname), ip: ip)
                let dnsName = resolvedName.flatMap { isMDNSName($0) ? nil : $0 }
                let mdnsName = resolvedName.flatMap { isMDNSName($0) ? $0 : nil }
                continuation.resume(
                    returning: Resolution(
                        hostname: mdnsName ?? dnsName,
                        dnsName: dnsName,
                        mdnsName: mdnsName
                    )
                )
            } else {
                continuation.resume(returning: Resolution(hostname: nil, dnsName: nil, mdnsName: nil))
            }
        }
    }

    /// Resolves a batch of IP addresses concurrently using a Swift task group.
    ///
    /// If DNS and mDNS resolution both fail for a given IP, the method falls back to
    /// any hostname that the ARP cache may have recorded for that address.
    ///
    /// - Parameter ips: The IPv4 addresses to resolve.
    /// - Returns: A dictionary keyed by IP address containing each successful resolution.
    static func resolveMany(ips: [String]) async -> [String: Resolution] {
        var results: [String: Resolution] = [:]
        let arpHostnames = await ARPResolver.resolveHostnames()

        await withTaskGroup(of: (String, Resolution).self) { group in
            for ip in ips {
                group.addTask { (ip, await resolve(ip: ip)) }
            }
            for await (ip, resolution) in group {
                if resolution.hostname != nil || resolution.dnsName != nil || resolution.mdnsName != nil {
                    results[ip] = resolution
                } else if let arpName = arpHostnames[ip] {
                    results[ip] = splitResolvedName(arpName, ip: ip)
                }
            }
        }
        return results
    }

    private static func resolveViaHost(ip: String) -> String? {
        let names = Host(address: ip).names
        return names.lazy
            .compactMap { normalize($0, ip: ip) }
            .first
    }

    private static func splitResolvedName(_ name: String, ip: String) -> Resolution {
        let resolvedName = normalize(name, ip: ip)
        let dnsName = resolvedName.flatMap { isMDNSName($0) ? nil : $0 }
        let mdnsName = resolvedName.flatMap { isMDNSName($0) ? $0 : nil }
        return Resolution(
            hostname: mdnsName ?? dnsName,
            dnsName: dnsName,
            mdnsName: mdnsName
        )
    }

    private static func normalize(_ name: String, ip: String) -> String? {
        let trimmed = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !trimmed.isEmpty, trimmed != ip else { return nil }
        return trimmed
    }

    private static func isMDNSName(_ name: String) -> Bool {
        name.lowercased().hasSuffix(".local")
    }
}
