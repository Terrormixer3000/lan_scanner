// LAN Scanner — DeviceListView.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import SwiftUI

/// Sortable, searchable table of all discovered devices shown in the centre pane.
///
/// When no devices have been discovered yet, an empty-state view is shown instead.
/// Column sort state is stored locally and applied to `scanner.devices` whenever the
/// sort order changes.
struct DeviceListView: View {
    @ObservedObject var scanner: NetworkScanner
    @Binding var selectedDevice: NetworkDevice?
    @Binding var selectedDeviceIDs: Set<NetworkDevice.ID>
    @Binding var searchText: String
    @State private var sortOrder = [KeyPathComparator(\NetworkDevice.ipAddress)]
    @SceneStorage("device-list-column-customization")
    private var columnCustomization = TableColumnCustomization<NetworkDevice>()

    var filteredDevices: [NetworkDevice] {
        if searchText.isEmpty { return scanner.devices }
        let q = searchText.lowercased()
        return scanner.devices.filter {
            $0.ipAddress.contains(q) ||
            ($0.macAddress?.lowercased().contains(q) ?? false) ||
            $0.displayName.lowercased().contains(q) ||
            ($0.dnsName?.lowercased().contains(q) ?? false) ||
            ($0.mdnsName?.lowercased().contains(q) ?? false) ||
            ($0.vendor?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        Group {
            if scanner.devices.isEmpty && !scanner.isScanning {
                emptyState
            } else {
                deviceTable
            }
        }
        .navigationTitle("LAN Scanner")
        .onChange(of: sortOrder) {
            scanner.devices.sort(using: sortOrder)
        }
        .onChange(of: selectedDeviceIDs) { _, newIDs in
            selectedDevice = scanner.devices.first { newIDs.contains($0.id) }
        }
        .onCopyCommand {
            copySelectionItemProviders()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Devices Found", systemImage: "wifi.slash")
        } description: {
            Text("Select a network and tap Scan to discover devices")
        } actions: {
            Button("Scan Now") { scanner.startScan() }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var deviceTable: some View {
        Table(
            filteredDevices,
            selection: $selectedDeviceIDs,
            sortOrder: $sortOrder,
            columnCustomization: $columnCustomization
        ) {
            TableColumn("IP Address", value: \NetworkDevice.ipAddress) { device in
                HStack {
                    Circle()
                        .fill(device.isOnline ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(device.ipAddress)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .width(min: 110, ideal: 130)
            .customizationID("ip-address")

            TableColumn("Hostname", value: \NetworkDevice.sortableHostname) { device in
                Text(device.hostname ?? "—")
                    .foregroundStyle(device.hostname == nil ? .secondary : .primary)
            }
            .width(min: 120, ideal: 180)
            .customizationID("hostname")

            TableColumn("MAC Address", value: \NetworkDevice.sortableMACAddress) { device in
                Text(device.macAddress ?? "—")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 140, ideal: 160)
            .customizationID("mac-address")

            TableColumn("Vendor", value: \NetworkDevice.sortableVendor) { device in
                Text(device.vendor ?? "—")
            }
            .width(min: 100, ideal: 150)
            .customizationID("vendor")

            TableColumn("Latency", value: \NetworkDevice.sortableLatency) { device in
                latencyCell(device)
            }
            .width(70)
            .customizationID("latency")

            TableColumn("Ports", value: \NetworkDevice.sortablePorts) { device in
                portsCell(device)
            }
            .width(min: 80, ideal: 120)
            .customizationID("ports")

            TableColumn("DNS", value: \NetworkDevice.sortableDNSName) { device in
                Text(device.dnsName ?? "—")
                    .foregroundStyle(device.dnsName == nil ? .secondary : .primary)
            }
            .width(min: 140, ideal: 200)
            .customizationID("dns")

            TableColumn("mDNS", value: \NetworkDevice.sortableMDNSName) { device in
                Text(device.mdnsName ?? "—")
                    .foregroundStyle(device.mdnsName == nil ? .secondary : .primary)
            }
            .width(min: 140, ideal: 200)
            .customizationID("mdns")
        }
        .contextMenu(forSelectionType: NetworkDevice.ID.self) { _ in
            Button("Copy as CSV") {
                copySelectionToPasteboard()
            }
            .disabled(selectedDeviceIDs.isEmpty)
        } primaryAction: { _ in
            if let firstSelectedID = selectedDeviceIDs.first {
                selectedDevice = scanner.devices.first { $0.id == firstSelectedID }
            }
        }
    }

    private func copySelectionToPasteboard() {
        let selectedDevices = filteredDevices.filter { selectedDeviceIDs.contains($0.id) }
        guard !selectedDevices.isEmpty else { return }
        DeviceClipboard.copyCSV(devices: selectedDevices)
    }

    private func copySelectionItemProviders() -> [NSItemProvider] {
        let selectedDevices = filteredDevices.filter { selectedDeviceIDs.contains($0.id) }
        guard !selectedDevices.isEmpty else { return [] }
        return DeviceClipboard.csvItemProviders(devices: selectedDevices)
    }

    @ViewBuilder
    private func latencyCell(_ device: NetworkDevice) -> some View {
        if let ms = device.latency {
            Text(String(format: "%.1f ms", ms))
                .foregroundStyle(ms < 10 ? .green : ms < 50 ? .orange : .red)
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func portsCell(_ device: NetworkDevice) -> some View {
        if device.openPorts.isEmpty {
            Text("—").foregroundStyle(.secondary)
        } else {
            Text(device.openPorts.map(String.init).joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
