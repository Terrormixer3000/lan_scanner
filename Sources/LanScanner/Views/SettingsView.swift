// LAN Scanner — SettingsView.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import SwiftUI

/// The preferences window opened via ⌘, (Settings scene).
///
/// All values are persisted to `UserDefaults` through `@AppStorage` and are
/// read directly by `PingHelper` and `NetworkScanner` at scan time.
struct SettingsView: View {
    @AppStorage("scanConcurrency") private var concurrency: Int = 50
    @AppStorage("pingTimeout") private var pingTimeout: Double = 1.0
    @AppStorage("autoRefreshEnabled") private var autoRefreshEnabled: Bool = false
    @AppStorage("autoRefreshInterval") private var autoRefreshInterval: Double = 60

    var body: some View {
        Form {
            Section("Scanning") {
                Stepper("Concurrency: \(concurrency)", value: $concurrency, in: 10...200, step: 10)
                HStack {
                    Text("Ping Timeout: \(pingTimeout, specifier: "%.1f")s")
                    Slider(value: $pingTimeout, in: 0.2...3.0, step: 0.1)
                }
            }
            Section("Auto Refresh") {
                Toggle("Enable Auto Refresh", isOn: $autoRefreshEnabled)
                if autoRefreshEnabled {
                    HStack {
                        Text("Interval: \(Int(autoRefreshInterval))s")
                        Slider(value: $autoRefreshInterval, in: 30...600, step: 30)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
        .navigationTitle("Settings")
    }
}
