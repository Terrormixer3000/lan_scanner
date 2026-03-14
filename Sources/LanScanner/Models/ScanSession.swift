// LAN Scanner — ScanSession.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import Foundation

/// An immutable snapshot of a completed network scan, stored in scan history.
///
/// `ScanSession` records which subnet was scanned, when the scan finished, and
/// the full list of devices that were discovered. Older sessions are serialised
/// to JSON and stored in `~/Library/Application Support/LanScanner/history.json`.
/// The history is capped at 50 entries by `NetworkScanner`.
struct ScanSession: Identifiable, Codable, Sendable {
    /// Unique identifier for this session.
    let id: UUID
    /// When the scan completed.
    let timestamp: Date
    /// The CIDR subnet that was scanned (e.g. `"192.168.1.0/24"`).
    let subnet: String
    /// All devices that were found during this scan, including offline hosts if any were tracked.
    let devices: [NetworkDevice]

    /// Total number of devices recorded in this session.
    var deviceCount: Int { devices.count }
    /// Number of devices that were online (responded to ping) during this session.
    var onlineCount: Int { devices.filter(\.isOnline).count }
}
