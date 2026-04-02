// LAN Scanner — PingHelper.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import Foundation

/// The result of a single ICMP ping to one host.
struct PingResult: Sendable {
    /// Whether the host responded within the timeout window.
    let alive: Bool
    /// Average round-trip latency in milliseconds, or `nil` if the host did not respond.
    let latency: Double?
    /// Hostname parsed from the ping response header, or `nil` if not available.
    let resolvedName: String?
}

/// Associates a ping result with the originating IP address for use in task group collection.
struct HostPingResult: Sendable {
    /// The target IPv4 address.
    let ip: String
    /// Average round-trip latency in milliseconds, or `nil` if the host timed out.
    let latency: Double?
    /// Hostname parsed from the ping output, or `nil`.
    let resolvedName: String?
}

/// Provides ICMP ping functionality by shelling out to the system `/sbin/ping` binary.
///
/// Because Swift does not expose raw ICMP sockets without elevated privileges, LAN Scanner
/// instead launches the setuid `/sbin/ping` utility as a subprocess and parses its output.
enum PingHelper {
    /// Pings a single host once and returns the result.
    ///
    /// Equivalent to `ping -c 1 -W 500 -t 1 <ip>`. The average round-trip time is
    /// extracted from the `round-trip min/avg/max/stddev` summary line.
    ///
    /// - Parameter ip: The IPv4 address to ping.
    /// - Returns: A `PingResult` indicating liveness, latency, and any resolved hostname.
    static func pingHost(_ ip: String) async -> PingResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = ["-c", "1", "-W", "500", "-t", "1", ip]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    var latency: Double? = nil
                    let resolvedName = parsedResolvedName(from: output, ip: ip)
                    if let rangeRT = output.range(of: "round-trip"),
                       let numRange = output.range(of: "= ", range: rangeRT.upperBound..<output.endIndex) {
                        let after = output[numRange.upperBound...]
                        let parts = after.split(separator: "/")
                        if parts.count >= 2, let avg = Double(parts[1]) {
                            latency = avg
                        }
                    }
                    continuation.resume(
                        returning: PingResult(alive: true, latency: latency, resolvedName: resolvedName)
                    )
                } else {
                    continuation.resume(returning: PingResult(alive: false, latency: nil, resolvedName: nil))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: PingResult(alive: false, latency: nil, resolvedName: nil))
            }
        }
    }

    /// Pings every host in a CIDR subnet concurrently and returns only the responsive ones.
    ///
    /// Up to `maxConcurrency` pings run in parallel. The `progress` closure is called after
    /// each host completes with a value in `0.0...1.0`.
    ///
    /// - Parameters:
    ///   - cidr: The subnet in CIDR notation (e.g. `"192.168.1.0/24"`).
    ///   - maxConcurrency: Maximum number of simultaneous ping subprocesses.
    ///   - progress: Called on each completion with the fraction of hosts probed so far.
    ///   - onDiscovery: Called immediately when a host responds successfully.
    /// - Returns: An array of `HostPingResult` for every host that responded.
    static func sweepSubnet(
        _ cidr: String,
        maxConcurrency: Int = 50,
        progress: @escaping @Sendable (Double) -> Void,
        onDiscovery: (@Sendable (HostPingResult) -> Void)? = nil
    ) async -> [HostPingResult] {
        let ips = expandCIDR(cidr)
        guard !ips.isEmpty else { return [] }

        let total = Double(ips.count)
        let counter = Counter()
        var results: [HostPingResult] = []

        await withTaskGroup(of: Optional<HostPingResult>.self) { group in
            var index = 0
            var active = 0

            while index < ips.count || active > 0 {
                while active < maxConcurrency && index < ips.count {
                    let ip = ips[index]
                    group.addTask {
                        let result = await pingHost(ip)
                        let completed = await counter.increment()
                        progress(Double(completed) / total)
                        if result.alive {
                            let hostResult = HostPingResult(
                                ip: ip,
                                latency: result.latency,
                                resolvedName: result.resolvedName
                            )
                            onDiscovery?(hostResult)
                            return hostResult
                        }
                        return nil
                    }
                    index += 1
                    active += 1
                }

                if let result = await group.next() {
                    active -= 1
                    if let r = result {
                        results.append(r)
                    }
                }
            }
        }

        return results.sorted {
            $0.ip.localizedStandardCompare($1.ip) == .orderedAscending
        }
    }

    private static func parsedResolvedName(from output: String, ip: String) -> String? {
        guard let firstLine = output.components(separatedBy: .newlines).first else { return nil }
        let pattern = #"^PING\s+(.+?)\s+\((\d+\.\d+\.\d+\.\d+)\)"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: firstLine,
                range: NSRange(location: 0, length: firstLine.utf16.count)
            ),
            match.numberOfRanges >= 3
        else {
            return nil
        }

        let line = firstLine as NSString
        let name = line.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedIP = line.substring(with: match.range(at: 2))
        guard !name.isEmpty, name != ip, resolvedIP == ip else { return nil }
        return name
    }

    static func expandCIDR(_ cidr: String) -> [String] {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              prefix >= 8, prefix <= 30 else { return [] }

        let ipStr = String(parts[0])
        let ipParts = ipStr.split(separator: ".").compactMap { UInt32($0) }
        guard ipParts.count == 4 else { return [] }

        let ip32 = (ipParts[0] << 24) | (ipParts[1] << 16) | (ipParts[2] << 8) | ipParts[3]
        let mask32 = prefix == 32 ? UInt32.max : (UInt32.max << (32 - prefix))
        let network = ip32 & mask32
        let broadcast = network | ~mask32

        var ips: [String] = []
        for addr in (network + 1)..<broadcast {
            let o1 = (addr >> 24) & 0xFF
            let o2 = (addr >> 16) & 0xFF
            let o3 = (addr >> 8) & 0xFF
            let o4 = addr & 0xFF
            ips.append("\(o1).\(o2).\(o3).\(o4)")
        }
        return ips
    }
}
