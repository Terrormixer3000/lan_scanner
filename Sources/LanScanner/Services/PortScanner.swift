// LAN Scanner — PortScanner.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import Foundation
import Network

/// Performs concurrent TCP port scanning using Apple’s Network framework (`NWConnection`).
///
/// Scanning is non-privileged and works by attempting a full TCP handshake. Ports that
/// complete the handshake within the timeout window are considered open. A `LockIsolated`
/// flag prevents the continuation from being resumed more than once per port in edge cases
/// where both the state handler and the timeout fire close together.
enum PortScanner {
    /// The 27 TCP ports scanned by default, paired with their common service names.
    static let commonPorts: [(port: Int, service: String)] = [
        (21, "FTP"), (22, "SSH"), (23, "Telnet"), (25, "SMTP"),
        (53, "DNS"), (80, "HTTP"), (110, "POP3"), (143, "IMAP"),
        (443, "HTTPS"), (445, "SMB"), (548, "AFP"), (554, "RTSP"),
        (631, "IPP/CUPS"), (993, "IMAPS"), (995, "POP3S"),
        (1883, "MQTT"), (3000, "HTTP-Dev"), (3306, "MySQL"),
        (3389, "RDP"), (5000, "UPnP/Dev"), (5900, "VNC"),
        (6379, "Redis"), (8080, "HTTP-Alt"), (8443, "HTTPS-Alt"),
        (8888, "HTTP-Dev"), (9100, "Printer"), (27017, "MongoDB")
    ]

    /// Tests whether a single TCP port is open on the given host.
    ///
    /// The connection is cancelled after `timeoutSeconds` if no definitive state is reached.
    ///
    /// - Parameters:
    ///   - ip: The target IPv4 address.
    ///   - port: The TCP port number to probe.
    ///   - timeoutSeconds: Maximum seconds to wait for the TCP handshake.
    /// - Returns: `true` if the port accepted the connection, `false` otherwise.
    static func scanPort(_ ip: String, port: Int, timeoutSeconds: Double = 1.5) async -> Bool {
        await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host(ip)
            let portEndpoint = NWEndpoint.Port(integerLiteral: UInt16(port))
            let connection = NWConnection(host: host, port: portEndpoint, using: .tcp)
            let resumed = LockIsolated(false)

            let timer = DispatchWorkItem {
                let shouldResume = resumed.withLock { val -> Bool in
                    if val { return false }
                    val = true
                    return true
                }
                if shouldResume {
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timer)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    timer.cancel()
                    let shouldResume = resumed.withLock { val -> Bool in
                        if val { return false }
                        val = true
                        return true
                    }
                    if shouldResume {
                        connection.cancel()
                        continuation.resume(returning: true)
                    }
                case .failed, .cancelled:
                    timer.cancel()
                    let shouldResume = resumed.withLock { val -> Bool in
                        if val { return false }
                        val = true
                        return true
                    }
                    if shouldResume {
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    /// Scans all ports in `commonPorts` concurrently and returns the open ones sorted.
    ///
    /// - Parameters:
    ///   - ip: The target IPv4 address.
    ///   - progress: Optional closure called after each port with the fraction completed so far.
    /// - Returns: Sorted array of open TCP port numbers.
    static func scanCommonPorts(
        ip: String,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async -> [Int] {
        var openPorts: [Int] = []
        let total = Double(commonPorts.count)
        let counter = Counter()

        await withTaskGroup(of: (Int, Bool).self) { group in
            for (port, _) in commonPorts {
                group.addTask {
                    let open = await scanPort(ip, port: port)
                    return (port, open)
                }
            }
            for await (port, open) in group {
                let completed = await counter.increment()
                progress?(Double(completed) / total)
                if open { openPorts.append(port) }
            }
        }
        return openPorts.sorted()
    }
}
