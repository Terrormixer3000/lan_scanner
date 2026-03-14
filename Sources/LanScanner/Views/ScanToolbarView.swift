// LAN Scanner — ScanToolbarView.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import SwiftUI

/// The main toolbar content placed above the device list.
///
/// Contains (left-to-right):
/// - `NetworkSelectorView` in the navigation area for choosing the target subnet.
/// - A scan/stop button with an inline progress indicator while scanning.
/// - An export button that presents `ExportView` in a popover.
/// - A details-panel toggle button.
struct ScanToolbarView: ToolbarContent {
    @ObservedObject var scanner: NetworkScanner
    @Binding var showExport: Bool
    @Binding var showsDetails: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            NetworkSelectorView(scanner: scanner)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if scanner.isScanning {
                ProgressView(value: scanner.progress)
                    .controlSize(.small)
                    .frame(width: 80)
                    .padding(.horizontal, 4)
                    .progressViewStyle(.linear)

                Button("Stop", systemImage: "stop.fill", action: { scanner.stopScan() })
                    .buttonStyle(.bordered)
            } else {
                Button {
                    scanner.startScan()
                } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                }
                .help("Scan")
                .buttonStyle(.bordered)
                .disabled(scanner.activeCIDR.isEmpty)
            }

            Button {
                showExport = true
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Export")
            .disabled(scanner.devices.isEmpty)
            .popover(isPresented: $showExport) {
                ExportView(scanner: scanner)
                    .frame(width: 220)
                    .padding()
            }
            .buttonStyle(.bordered)

            Button {
                showsDetails.toggle()
            } label: {
                Image(systemName: showsDetails ? "sidebar.right" : "rectangle.leadinghalf.filled")
            }
            .help(showsDetails ? "Hide Details" : "Show Details")
            .buttonStyle(.bordered)
        }
    }
}
