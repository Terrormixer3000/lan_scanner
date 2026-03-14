// LAN Scanner — NetworkDevice.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import Foundation

/// Represents a single device discovered on the local network during a scan.
///
/// `NetworkDevice` is the core data model of LAN Scanner. It aggregates all
/// information gathered during the multi-phase scan: IP/MAC addresses, resolved
/// hostnames (DNS, mDNS, Bonjour), vendor information, latency, open ports, and
/// any user-assigned label or notes. The struct is `Codable` so it can be
/// serialised to JSON for export and persistent storage.
struct NetworkDevice: Identifiable, Codable, Equatable, Hashable, Sendable {
    /// The device's IPv4 address, which also serves as the unique identifier.
    var id: String { ipAddress }
    /// IPv4 address (e.g. `"192.168.1.42"`).
    var ipAddress: String
    /// Hardware (MAC) address in upper-case colon-separated format (e.g. `"AA:BB:CC:DD:EE:FF"`),
    /// or `nil` if the ARP cache returned no entry for this IP.
    var macAddress: String?
    /// Primary resolved hostname — prefers mDNS `.local` names, then DNS names.
    var hostname: String?
    /// Fully-qualified DNS name resolved via reverse lookup, if available.
    var dnsName: String?
    /// Bonjour / mDNS `.local` hostname, if the device advertises one.
    var mdnsName: String?
    /// Manufacturer name derived from the MAC address OUI prefix (e.g. `"Apple, Inc."`).
    var vendor: String?
    /// Average round-trip latency in milliseconds measured during the ping sweep.
    var latency: Double?
    /// Whether the device responded to ICMP ping during the most recent scan.
    var isOnline: Bool
    /// Sorted list of TCP port numbers found to be open during a port scan.
    var openPorts: [Int]
    /// Timestamp when this device was first observed by LAN Scanner.
    var firstSeen: Date
    /// Timestamp of the most recent successful contact with this device.
    var lastSeen: Date
    /// User-defined friendly label (e.g. `"Dad's iPhone"`).
    var label: String?
    /// Free-form notes the user has attached to this device.
    var notes: String?

    /// Creates a new `NetworkDevice` with the given IP address and all optional fields set to `nil`.
    /// - Parameter ipAddress: The IPv4 address of the newly discovered host.
    init(ipAddress: String) {
        self.ipAddress = ipAddress
        self.macAddress = nil
        self.hostname = nil
        self.dnsName = nil
        self.mdnsName = nil
        self.vendor = nil
        self.latency = nil
        self.isOnline = false
        self.openPorts = []
        self.firstSeen = Date()
        self.lastSeen = Date()
        self.label = nil
        self.notes = nil
    }

    /// The best human-readable name for this device.
    ///
    /// Resolution order: custom `label` → `preferredResolvedName` → raw `ipAddress`.
    var displayName: String {
        label ?? preferredResolvedName ?? ipAddress
    }

    /// The best automatically resolved name, ignoring user labels.
    ///
    /// Prefers `hostname` (which may already be an mDNS name), then `mdnsName`,
    /// then `dnsName`. Returns `nil` if no name could be resolved.
    var preferredResolvedName: String? {
        hostname ?? mdnsName ?? dnsName
    }
}
