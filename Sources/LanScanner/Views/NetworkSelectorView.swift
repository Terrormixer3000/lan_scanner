// LAN Scanner — NetworkSelectorView.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import SwiftUI

/// Compact toolbar control for selecting the network target.
///
/// A segmented picker switches between two modes:
/// - **Auto** — a dropdown lists all active network interfaces with their CIDR ranges.
/// - **CIDR** — a text field accepts a custom subnet such as `192.168.1.0/24`.
struct NetworkSelectorView: View {
    @ObservedObject var scanner: NetworkScanner

    var body: some View {
        HStack(spacing: 8) {
            Picker("Mode", selection: $scanner.useManualCIDR) {
                Text("Auto").tag(false)
                Text("CIDR").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 104)

            if scanner.useManualCIDR {
                TextField("192.168.1.0/24", text: $scanner.manualCIDR)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 180)
            } else {
                Picker("Interface", selection: $scanner.selectedInterface) {
                    ForEach(scanner.availableInterfaces) { iface in
                        Text("\(iface.displayName) · \(iface.cidr)")
                            .tag(Optional(iface))
                    }
                    Text("No Network").tag(Optional<NetworkInterface>.none)
                }
                .labelsHidden()
                .frame(width: 250)
            }
        }
        .controlSize(.small)
    }
}
