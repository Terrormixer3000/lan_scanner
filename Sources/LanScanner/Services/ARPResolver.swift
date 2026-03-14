// LAN Scanner — ARPResolver.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import Foundation

/// Queries the macOS ARP cache via `/usr/sbin/arp` to resolve MAC addresses and hostnames.
///
/// ARP (Address Resolution Protocol) maps IPv4 addresses to hardware MAC addresses.
/// After a ping sweep has identified live hosts, LAN Scanner calls `resolveAll()` to
/// retrieve the OS-cached IP→MAC mappings without sending additional network traffic.
enum ARPResolver {
    /// Returns a dictionary mapping IPv4 address strings to their MAC addresses.
    ///
    /// Runs `arp -a -n` (numeric mode, suppress DNS lookups) and parses lines of the form:
    /// `? (192.168.1.1) at aa:bb:cc:dd:ee:ff on en0 ...`
    ///
    /// Entries with an `(incomplete)` MAC are excluded.
    static func resolveAll() async -> [String: String] {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
            process.arguments = ["-a", "-n"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                var result: [String: String] = [:]

                let lines = output.components(separatedBy: "\n")
                let regex = try? NSRegularExpression(
                    pattern: #"\((\d+\.\d+\.\d+\.\d+)\)\s+at\s+([0-9a-fA-F:]+)"#
                )
                for line in lines {
                    let nsLine = line as NSString
                    let range = NSRange(location: 0, length: nsLine.length)
                    if let match = regex?.firstMatch(in: line, range: range),
                       match.numberOfRanges >= 3 {
                        let ip = nsLine.substring(with: match.range(at: 1))
                        let mac = nsLine.substring(with: match.range(at: 2))
                        if mac != "(incomplete)" && !mac.isEmpty {
                            result[ip] = mac.uppercased()
                        }
                    }
                }
                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: [:])
            }
        }
    }

    /// Returns a dictionary mapping IPv4 address strings to their ARP-cached hostnames.
    ///
    /// Runs `arp -a` (without `-n` so the OS resolves hostnames) and parses lines of the form:
    /// `hostname.local (192.168.1.42) at ...`
    /// Entries where the hostname equals the IP address are excluded.
    static func resolveHostnames() async -> [String: String] {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
            process.arguments = ["-a"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                var result: [String: String] = [:]

                let lines = output.components(separatedBy: "\n")
                let regex = try? NSRegularExpression(
                    pattern: #"^([^\s?][^\s]*)\s+\((\d+\.\d+\.\d+\.\d+)\)"#
                )

                for line in lines {
                    let nsLine = line as NSString
                    let range = NSRange(location: 0, length: nsLine.length)
                    guard
                        let match = regex?.firstMatch(in: line, range: range),
                        match.numberOfRanges >= 3
                    else {
                        continue
                    }

                    let name = nsLine.substring(with: match.range(at: 1))
                    let ip = nsLine.substring(with: match.range(at: 2))
                    if !name.isEmpty, name != ip {
                        result[ip] = name
                    }
                }

                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: [:])
            }
        }
    }
}
