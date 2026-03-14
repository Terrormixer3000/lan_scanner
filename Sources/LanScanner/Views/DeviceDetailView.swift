// LAN Scanner — DeviceDetailView.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import SwiftUI
import AppKit

/// Detail panel for a selected device, shown in the right pane.
///
/// Displays a header with the device name and online status, a two-column info grid,
/// quick-action buttons (open HTTP/HTTPS, copy IP/MAC), an on-demand TCP port scanner,
/// and an editable label/notes section.
struct DeviceDetailView: View {
    let device: NetworkDevice
    @ObservedObject var scanner: NetworkScanner
    @State private var labelText: String = ""
    @State private var notesText: String = ""
    @State private var isPortScanning = false
    @State private var portScanProgress: Double = 0
    @State private var scannedPorts: [Int] = []
    @State private var portScanTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text(device.displayName)
                            .font(.title2.bold())
                        HStack {
                            Circle()
                                .fill(device.isOnline ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(device.isOnline ? "Online" : "Offline")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let vendor = device.vendor {
                        Text(vendor)
                            .font(.caption)
                            .padding(6)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }

                Divider()

                // Info Grid
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 12
                ) {
                    InfoRow(label: "IP Address", value: device.ipAddress, mono: true)
                    InfoRow(label: "MAC Address", value: device.macAddress ?? "Unknown", mono: true)
                    InfoRow(label: "Hostname", value: device.hostname ?? "Unknown")
                    InfoRow(label: "DNS Name", value: device.dnsName ?? "Unknown")
                    InfoRow(label: "mDNS Name", value: device.mdnsName ?? "Unknown")
                    InfoRow(label: "Vendor", value: device.vendor ?? "Unknown")
                    if let latency = device.latency {
                        InfoRow(label: "Latency", value: String(format: "%.2f ms", latency))
                    }
                    InfoRow(
                        label: "First Seen",
                        value: device.firstSeen.formatted(date: .abbreviated, time: .shortened)
                    )
                    InfoRow(
                        label: "Last Seen",
                        value: device.lastSeen.formatted(date: .abbreviated, time: .shortened)
                    )
                }

                Divider()

                // Quick Actions
                Text("Quick Actions").font(.headline)
                HStack(spacing: 10) {
                    Button {
                        if let url = URL(string: "http://\(device.ipAddress)") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Open HTTP", systemImage: "safari")
                    }
                    Button {
                        if let url = URL(string: "https://\(device.ipAddress)") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Open HTTPS", systemImage: "lock.shield")
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(device.ipAddress, forType: .string)
                    } label: {
                        Label("Copy IP", systemImage: "doc.on.doc")
                    }
                    if let mac = device.macAddress {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(mac, forType: .string)
                        } label: {
                            Label("Copy MAC", systemImage: "doc.on.doc")
                        }
                    }
                }
                .buttonStyle(.bordered)

                Divider()

                // Port Scanner
                HStack {
                    Text("Port Scanner").font(.headline)
                    Spacer()
                    if isPortScanning {
                        ProgressView(value: portScanProgress).frame(width: 100)
                        Button("Stop") {
                            portScanTask?.cancel()
                            isPortScanning = false
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Scan Ports") { startPortScan() }
                            .buttonStyle(.borderedProminent)
                    }
                }

                if !scannedPorts.isEmpty {
                    let serviceMap = Dictionary(
                        uniqueKeysWithValues: PortScanner.commonPorts.map { ($0.port, $0.service) }
                    )
                    FlowLayout(spacing: 6) {
                        ForEach(scannedPorts, id: \.self) { port in
                            HStack(spacing: 3) {
                                Text("\(port)")
                                    .font(.system(.caption, design: .monospaced).bold())
                                if let svc = serviceMap[port] {
                                    Text(svc).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.15))
                            .clipShape(Capsule())
                        }
                    }
                }

                Divider()

                // Labels & Notes
                Text("Label & Notes").font(.headline)
                TextField("Custom label (e.g. 'Dad's iPhone')", text: $labelText)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $notesText)
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

                Button("Save Label") {
                    if let mac = device.macAddress {
                        scanner.saveLabel(mac: mac, label: labelText, notes: notesText)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .onAppear {
            labelText = device.label ?? ""
            notesText = device.notes ?? ""
            scannedPorts = device.openPorts
        }
        .onChange(of: device.id) {
            labelText = device.label ?? ""
            notesText = device.notes ?? ""
            scannedPorts = device.openPorts
            isPortScanning = false
            portScanProgress = 0
        }
    }

    private func startPortScan() {
        scannedPorts = []
        isPortScanning = true
        portScanProgress = 0
        portScanTask = Task {
            let ports = await PortScanner.scanCommonPorts(ip: device.ipAddress) { p in
                Task { @MainActor in portScanProgress = p }
            }
            await MainActor.run {
                scannedPorts = ports
                scanner.saveOpenPorts(for: device.id, ports: ports)
                isPortScanning = false
            }
        }
    }
}

/// A single labelled info row used in the device detail grid.
///
/// The value text supports text selection and offers a context menu with
/// "Copy Value" and "Copy Field" actions.
struct InfoRow: View {
    let label: String
    let value: String
    var mono: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(mono ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
        }
        .contextMenu {
            Button {
                copyToPasteboard(value)
            } label: {
                Label("Copy Value", systemImage: "doc.on.doc")
            }

            Button {
                copyToPasteboard("\(label): \(value)")
            } label: {
                Label("Copy Field", systemImage: "list.bullet.clipboard")
            }
        }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

/// A custom `Layout` that flows child views horizontally, wrapping to the next
/// row when there is not enough remaining width.
///
/// Used in `DeviceDetailView` to display open port tags without clipping.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
