// LAN Scanner — SettingsView.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import SwiftUI
import Sparkle

/// The preferences window opened via ⌘, (Settings scene).
///
/// All values are persisted to `UserDefaults` through `@AppStorage` and are
/// read directly by `PingHelper` and `NetworkScanner` at scan time.
/// The Updates section exposes Sparkle's automatic-check toggle and a manual check button.
struct SettingsView: View {
    @AppStorage("scanConcurrency") private var concurrency: Int = 50
    @AppStorage("pingTimeout") private var pingTimeout: Double = 1.0
    @AppStorage("autoRefreshEnabled") private var autoRefreshEnabled: Bool = false
    @AppStorage("autoRefreshInterval") private var autoRefreshInterval: Double = 60

    /// The Sparkle updater instance, passed from `LanScannerApp`.
    let updater: SPUUpdater
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

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
            Section("Updates") {
                Toggle("Check for updates automatically",
                       isOn: Binding(
                           get: { updater.automaticallyChecksForUpdates },
                           set: { updater.automaticallyChecksForUpdates = $0 }
                       ))
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!checkForUpdatesViewModel.canCheckForUpdates)

                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
                Text("Current version: \(version)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 350)
        .navigationTitle("Settings")
    }
}
