// LAN Scanner — NetworkInterface.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import Foundation

/// Describes an active macOS network interface that is suitable for scanning.
///
/// Instances are created by `NetworkInterfaceManager.getActiveInterfaces()` and
/// presented to the user in `NetworkSelectorView` so they can pick which subnet
/// to scan. Only IPv4 interfaces that are up and not loopback are included.
struct NetworkInterface: Identifiable, Hashable, Equatable, Sendable {
    /// The BSD interface name (e.g. `"en0"`, `"en1"`, `"utun2"`). Used as the stable identifier.
    let id: String
    /// Human-readable label shown in the UI (e.g. `"Wi-Fi (en0)"`, `"VPN (utun2)"`).
    let displayName: String
    /// IPv4 address assigned to this interface (e.g. `"192.168.1.10"`).
    let ipAddress: String
    /// Subnet mask in dotted-decimal notation (e.g. `"255.255.255.0"`).
    let subnetMask: String
    /// CIDR notation for the network this interface belongs to (e.g. `"192.168.1.0/24"`).
    let cidr: String
    /// `true` when the interface name begins with `"en"`, which covers Wi-Fi and Ethernet on macOS.
    let isWifi: Bool
}
