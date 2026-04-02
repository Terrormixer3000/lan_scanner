// LAN Scanner — NetworkScanner.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import Foundation
import SwiftUI
import UserNotifications

/// Persisted label and notes for a specific device, keyed by MAC address.
struct DeviceLabel: Codable, Sendable {
    var label: String
    var notes: String
}

/// The central state object that orchestrates network scanning and owns all published UI state.
///
/// `NetworkScanner` is an `@MainActor`-isolated `ObservableObject`. It coordinates the four
/// scan phases (ping sweep → ARP → hostname/Bonjour resolution → vendor lookup), manages
/// persistent storage of device labels and scan history, and triggers user notifications
/// when new devices are detected.
@MainActor
final class NetworkScanner: ObservableObject {
    // MARK: - Published state

    /// All devices discovered in the most recent scan.
    @Published var devices: [NetworkDevice] = []
    /// `true` while a scan is in progress.
    @Published var isScanning: Bool = false
    /// Fractional scan progress from `0.0` (not started) to `1.0` (complete).
    @Published var progress: Double = 0
    /// Human-readable description of the current scan phase shown in the status bar.
    @Published var statusMessage: String = "Ready"
    /// The network interface currently selected for scanning.
    @Published var selectedInterface: NetworkInterface?
    /// All active network interfaces available for selection.
    @Published var availableInterfaces: [NetworkInterface] = []
    /// User-entered CIDR subnet used when `useManualCIDR` is `true`.
    @Published var manualCIDR: String = ""
    /// When `true`, `manualCIDR` is used instead of the selected interface’s CIDR.
    @Published var useManualCIDR: Bool = false
    /// Scan history, sorted newest-first, capped at 50 entries.
    @Published var scanHistory: [ScanSession] = []
    /// User-assigned labels and notes keyed by device MAC address.
    @Published var deviceLabels: [String: DeviceLabel] = [:]

    private var scanTask: Task<Void, Never>?
    private let vendorLookup = VendorLookup.shared

    /// The CIDR subnet that will be used for the next scan.
    ///
    /// Returns `manualCIDR` when `useManualCIDR` is `true`, otherwise falls back
    /// to the selected interface’s `cidr` property. An empty string means no
    /// network is selected and scanning is disabled.
    var activeCIDR: String {
        if useManualCIDR && !manualCIDR.isEmpty { return manualCIDR }
        return selectedInterface?.cidr ?? ""
    }

    init() {
        loadInterfaces()
        loadLabels()
        loadHistory()
    }

    /// Refreshes the list of available network interfaces and pre-selects the first one
    /// if no interface has been chosen yet (or the previously selected one disappeared).
    func loadInterfaces() {
        availableInterfaces = NetworkInterfaceManager.getActiveInterfaces()
        if selectedInterface == nil || !availableInterfaces.contains(where: { $0.id == selectedInterface?.id }) {
            selectedInterface = availableInterfaces.first
        }
    }

    /// Starts a new scan on `activeCIDR` unless one is already running.
    func startScan() {
        guard !isScanning else { return }
        scanTask = Task { await performScan() }
    }

    /// Cancels the running scan task and resets the scanning state.
    func stopScan() {
        scanTask?.cancel()
        isScanning = false
        statusMessage = "Scan stopped"
    }

    private func performScan() async {
        guard !activeCIDR.isEmpty else {
            statusMessage = "No network selected"
            return
        }

        isScanning = true
        progress = 0
        statusMessage = "Pinging hosts..."
        devices = []

        let cidr = activeCIDR
        let subnetIPs = Set(PingHelper.expandCIDR(cidr))
        var aliveHostsByIP: [String: HostPingResult] = [:]
        var arpTable: [String: String] = [:]
        var bonjourHostnames: [String: String] = [:]
        var hostnames: [String: HostnameResolver.Resolution] = [:]

        // Phase 1: Ping sweep
        let aliveHosts = await PingHelper.sweepSubnet(
            cidr,
            maxConcurrency: 50,
            progress: { [weak self] p in
                Task { @MainActor [weak self] in
                    self?.progress = p * 0.5
                }
            },
            onDiscovery: { [weak self] host in
                Task { @MainActor [weak self] in
                    self?.upsertPingDiscoveredDevice(host)
                }
            }
        )

        aliveHostsByIP = Dictionary(uniqueKeysWithValues: aliveHosts.map { ($0.ip, $0) })
        rebuildDevices(
            candidateIPs: Set(aliveHostsByIP.keys),
            aliveHostsByIP: aliveHostsByIP,
            arpTable: arpTable,
            hostnames: hostnames,
            bonjourHostnames: bonjourHostnames
        )

        guard !Task.isCancelled else { isScanning = false; return }
        statusMessage = "Resolving MAC addresses..."

        // Phase 2: ARP
        arpTable = await ARPResolver.resolveAll().filter { subnetIPs.contains($0.key) }
        rebuildDevices(
            candidateIPs: Set(aliveHostsByIP.keys).union(arpTable.keys),
            aliveHostsByIP: aliveHostsByIP,
            arpTable: arpTable,
            hostnames: hostnames,
            bonjourHostnames: bonjourHostnames
        )
        guard !Task.isCancelled else { isScanning = false; return }

        statusMessage = "Browsing Bonjour services..."
        progress = 0.6

        bonjourHostnames = await BonjourResolver.resolveHostnames(for: Array(subnetIPs))
        rebuildDevices(
            candidateIPs: Set(aliveHostsByIP.keys)
                .union(arpTable.keys)
                .union(bonjourHostnames.keys),
            aliveHostsByIP: aliveHostsByIP,
            arpTable: arpTable,
            hostnames: hostnames,
            bonjourHostnames: bonjourHostnames
        )
        guard !Task.isCancelled else { isScanning = false; return }

        statusMessage = "Resolving hostnames..."
        progress = 0.72

        let candidateIPs = Set(aliveHostsByIP.keys)
            .union(arpTable.keys)
            .union(bonjourHostnames.keys)
        let sortedCandidateIPs = candidateIPs.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        hostnames = await HostnameResolver.resolveMany(ips: sortedCandidateIPs)
        rebuildDevices(
            candidateIPs: candidateIPs,
            aliveHostsByIP: aliveHostsByIP,
            arpTable: arpTable,
            hostnames: hostnames,
            bonjourHostnames: bonjourHostnames
        )
        guard !Task.isCancelled else { isScanning = false; return }

        statusMessage = "Loading vendor database..."
        progress = 0.8
        await vendorLookup.prepare()
        guard !Task.isCancelled else { isScanning = false; return }

        statusMessage = "Looking up vendors..."
        progress = 0.85

        let newDevices = assembledDevices(
            sortedCandidateIPs: sortedCandidateIPs,
            aliveHostsByIP: aliveHostsByIP,
            arpTable: arpTable,
            hostnames: hostnames,
            bonjourHostnames: bonjourHostnames,
            vendorLookup: vendorLookup
        )
        devices = newDevices
        progress = 1.0
        isScanning = false
        statusMessage = "Scan complete — \(devices.count) device(s) found"

        let session = ScanSession(id: UUID(), timestamp: Date(), subnet: cidr, devices: newDevices)
        scanHistory.insert(session, at: 0)
        if scanHistory.count > 50 { scanHistory = Array(scanHistory.prefix(50)) }
        saveHistory()
        checkForNewDevices(newDevices)
    }

    private func upsertPingDiscoveredDevice(_ host: HostPingResult) {
        var device = devices.first(where: { $0.id == host.ip }) ?? NetworkDevice(ipAddress: host.ip)
        device.isOnline = true
        device.latency = host.latency

        if let pingName = host.resolvedName {
            device.hostname = pingName
            if pingName.lowercased().hasSuffix(".local") {
                device.mdnsName = pingName
                device.dnsName = nil
            } else {
                device.dnsName = pingName
                device.mdnsName = nil
            }
        }

        if let index = devices.firstIndex(where: { $0.id == host.ip }) {
            devices[index] = device
        } else {
            devices.append(device)
            devices.sort { $0.ipAddress.localizedStandardCompare($1.ipAddress) == .orderedAscending }
        }
    }

    private func rebuildDevices(
        candidateIPs: Set<String>,
        aliveHostsByIP: [String: HostPingResult],
        arpTable: [String: String],
        hostnames: [String: HostnameResolver.Resolution],
        bonjourHostnames: [String: String]
    ) {
        let sortedCandidateIPs = candidateIPs.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        devices = assembledDevices(
            sortedCandidateIPs: sortedCandidateIPs,
            aliveHostsByIP: aliveHostsByIP,
            arpTable: arpTable,
            hostnames: hostnames,
            bonjourHostnames: bonjourHostnames,
            vendorLookup: nil
        )
    }

    private func assembledDevices(
        sortedCandidateIPs: [String],
        aliveHostsByIP: [String: HostPingResult],
        arpTable: [String: String],
        hostnames: [String: HostnameResolver.Resolution],
        bonjourHostnames: [String: String],
        vendorLookup: VendorLookup?
    ) -> [NetworkDevice] {
        let labels = deviceLabels

        return sortedCandidateIPs.map { ip in
            let pingHost = aliveHostsByIP[ip]

            var device = NetworkDevice(ipAddress: ip)
            device.isOnline = pingHost != nil
            device.latency = pingHost?.latency
            device.macAddress = arpTable[ip]
            if let resolution = hostnames[ip] {
                device.hostname = resolution.hostname
                device.dnsName = resolution.dnsName
                device.mdnsName = resolution.mdnsName
            }

            if let bonjourName = bonjourHostnames[ip] {
                if device.hostname == nil {
                    device.hostname = bonjourName
                }
                if bonjourName.lowercased().hasSuffix(".local") {
                    if device.mdnsName == nil {
                        device.mdnsName = bonjourName
                    }
                } else if device.dnsName == nil {
                    device.dnsName = bonjourName
                }
            } else if let pingName = pingHost?.resolvedName {
                device.hostname = pingName
                if pingName.lowercased().hasSuffix(".local") {
                    device.mdnsName = pingName
                } else {
                    device.dnsName = pingName
                }
            }

            if let mac = device.macAddress {
                device.vendor = vendorLookup?.lookup(mac: mac)
                if let saved = labels[mac] {
                    device.label = saved.label.isEmpty ? nil : saved.label
                    device.notes = saved.notes.isEmpty ? nil : saved.notes
                }
            }

            return device
        }
    }

    /// Persists a custom label and notes for a device identified by its MAC address.
    ///
    /// Also updates the in-memory `devices` array immediately so the UI reflects the change.
    ///
    /// - Parameters:
    ///   - mac: The device’s MAC address (used as the persistent key).
    ///   - label: The user-supplied friendly name. An empty string clears the label.
    ///   - notes: Free-form notes text. An empty string clears the notes.
    func saveLabel(mac: String, label: String, notes: String) {
        deviceLabels[mac] = DeviceLabel(label: label, notes: notes)
        if let idx = devices.firstIndex(where: { $0.macAddress == mac }) {
            devices[idx].label = label.isEmpty ? nil : label
            devices[idx].notes = notes.isEmpty ? nil : notes
        }
        saveLabels()
    }

    /// Updates the open-ports list for a device after a port scan completes.
    ///
    /// Also updates `lastSeen` to the current date.
    ///
    /// - Parameters:
    ///   - deviceID: The `id` (IP address) of the target device.
    ///   - ports: The sorted list of open port numbers discovered.
    func saveOpenPorts(for deviceID: NetworkDevice.ID, ports: [Int]) {
        guard let idx = devices.firstIndex(where: { $0.id == deviceID }) else { return }
        devices[idx].openPorts = ports.sorted()
        devices[idx].lastSeen = Date()
    }

    /// Generates a CSV string for all currently discovered devices.
    ///
    /// The first row is a header. All field values are double-quoted.
    /// Multiple open ports are separated by semicolons within their cell.
    func exportCSV() -> String {
        DeviceExportFormatter.csv(from: devices)
    }

    /// Encodes the current device list as pretty-printed JSON data.
    ///
    /// - Returns: The encoded `Data`, or `nil` if encoding fails.
    func exportJSON() -> Data? {
        try? JSONEncoder().encode(devices)
    }

    private func checkForNewDevices(_ newDevices: [NetworkDevice]) {
        let knownMACs = Set(deviceLabels.keys)
        let unknownNew = newDevices.filter { d in
            guard let mac = d.macAddress else { return false }
            return !knownMACs.contains(mac)
        }
        if !unknownNew.isEmpty {
            sendNotification(count: unknownNew.count)
        }
    }

    private func sendNotification(count: Int) {
        guard AppRuntime.canUseUserNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = "LAN Scanner"
        content.body = "\(count) new device(s) discovered on your network"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Persistence
    private var appSupportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LanScanner")
    }
    private var labelsURL: URL { appSupportDir.appendingPathComponent("labels.json") }
    private var historyURL: URL { appSupportDir.appendingPathComponent("history.json") }

    private func ensureDir() {
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
    }

    private func saveLabels() {
        ensureDir()
        try? JSONEncoder().encode(deviceLabels).write(to: labelsURL)
    }

    private func loadLabels() {
        guard let data = try? Data(contentsOf: labelsURL),
              let saved = try? JSONDecoder().decode([String: DeviceLabel].self, from: data)
        else { return }
        deviceLabels = saved
    }

    private func saveHistory() {
        ensureDir()
        try? JSONEncoder().encode(Array(scanHistory.prefix(20))).write(to: historyURL)
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let saved = try? JSONDecoder().decode([ScanSession].self, from: data)
        else { return }
        scanHistory = saved
    }
}
