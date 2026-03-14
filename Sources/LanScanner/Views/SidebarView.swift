// LAN Scanner — SidebarView.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import SwiftUI

/// The left sidebar panel showing current scan stats and the last 10 scan history entries.
struct SidebarView: View {
    @ObservedObject var scanner: NetworkScanner

    var body: some View {
        List {
            Section("Current Scan") {
                Label("\(scanner.devices.filter(\.isOnline).count) Online", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("\(scanner.devices.count) Total Devices", systemImage: "desktopcomputer")
            }

            Section("Scan History") {
                if scanner.scanHistory.isEmpty {
                    Text("No history yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scanner.scanHistory.prefix(10)) { session in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption.bold())
                            Text("\(session.onlineCount) devices · \(session.subnet)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("LAN Scanner")
    }
}
