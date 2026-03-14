// LAN Scanner — BonjourResolver.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import Foundation
import Darwin

/// Discovers device hostnames through Bonjour / mDNS service browsing.
///
/// `BonjourResolver` launches a `NetServiceBrowser` for each of 16 common service
/// types (workstation announcements, SSH, SMB, AirPlay, HomeKit, etc.) and waits up
/// to `timeout` seconds for services to resolve. Resolved IP addresses that match
/// a target IP from the ping sweep are returned mapped to their Bonjour hostname.
@MainActor
enum BonjourResolver {
    /// Looks up Bonjour hostnames for a set of already-discovered IP addresses.
    ///
    /// - Parameters:
    ///   - ips: The IPv4 addresses to match against Bonjour service records.
    ///   - timeout: How long (in seconds) to wait for service resolution before stopping browsers.
    /// - Returns: A dictionary mapping IP address → resolved Bonjour hostname.
    static func resolveHostnames(for ips: [String], timeout: TimeInterval = 2.0) async -> [String: String] {
        let session = BonjourBrowseSession(targetIPs: Set(ips), timeout: timeout)
        return await session.run()
    }
}

@MainActor
private final class BonjourBrowseSession: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    private let targetIPs: Set<String>
    private let timeout: TimeInterval

    private var continuation: CheckedContinuation<[String: String], Never>?
    private var browsers: [NetServiceBrowser] = []
    private var services: [NetService] = []
    private var seenServices: Set<String> = []
    private var results: [String: String] = [:]
    private var finishTask: Task<Void, Never>?

    private let serviceTypes = [
        "_workstation._tcp.",
        "_device-info._tcp.",
        "_http._tcp.",
        "_https._tcp.",
        "_smb._tcp.",
        "_adisk._tcp.",
        "_airplay._tcp.",
        "_raop._tcp.",
        "_ssh._tcp.",
        "_rfb._tcp.",
        "_ipp._tcp.",
        "_printer._tcp.",
        "_googlecast._tcp.",
        "_hap._tcp.",
        "_companion-link._tcp.",
        "_matter._tcp."
    ]

    init(targetIPs: Set<String>, timeout: TimeInterval) {
        self.targetIPs = targetIPs
        self.timeout = timeout
    }

    func run() async -> [String: String] {
        guard !targetIPs.isEmpty else { return [:] }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            for serviceType in serviceTypes {
                let browser = NetServiceBrowser()
                browser.delegate = self
                browsers.append(browser)
                browser.searchForServices(ofType: serviceType, inDomain: "local.")
            }

            finishTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                finish()
            }
        }
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        let identifier = "\(service.domain)|\(service.type)|\(service.name)"
        guard seenServices.insert(identifier).inserted else { return }

        service.delegate = self
        services.append(service)
        service.resolve(withTimeout: 1.0)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let hostname = normalizeHostname(sender.hostName)
        let addresses = sender.addresses ?? []

        guard let hostname else {
            sender.stop()
            return
        }

        for ip in extractIPAddresses(from: addresses) where targetIPs.contains(ip) {
            if results[ip] == nil {
                results[ip] = hostname
            }
        }

        sender.stop()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        sender.stop()
    }

    private func finish() {
        finishTask?.cancel()
        finishTask = nil

        for browser in browsers {
            browser.stop()
        }
        browsers.removeAll()

        for service in services {
            service.stop()
        }
        services.removeAll()

        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: results)
    }

    private func normalizeHostname(_ hostname: String?) -> String? {
        guard let hostname else { return nil }
        let trimmed = hostname
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return trimmed.isEmpty ? nil : trimmed
    }

    private func extractIPAddresses(from addresses: [Data]) -> [String] {
        addresses.compactMap { data in
            data.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return nil }
                let socketAddress = baseAddress.assumingMemoryBound(to: sockaddr.self)
                let family = Int32(socketAddress.pointee.sa_family)

                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let length: socklen_t
                switch family {
                case AF_INET:
                    length = socklen_t(MemoryLayout<sockaddr_in>.size)
                case AF_INET6:
                    length = socklen_t(MemoryLayout<sockaddr_in6>.size)
                default:
                    return nil
                }

                let result = getnameinfo(
                    socketAddress,
                    length,
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                guard result == 0 else { return nil }

                let ip = String(cString: host)
                return ip.isEmpty ? nil : ip
            }
        }
    }
}
