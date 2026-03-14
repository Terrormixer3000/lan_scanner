// LAN Scanner — ExportView.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A small popover that lets the user export the current device list.
///
/// Provides two buttons: one to save a `.csv` file and one to save a `.json` file.
/// Both use `NSSavePanel` to let the user choose a destination.
struct ExportView: View {
    @ObservedObject var scanner: NetworkScanner
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Text("Export Devices").font(.headline)
            Button("Export as CSV") {
                let csv = scanner.exportCSV()
                saveFile(content: csv, ext: "csv", type: .commaSeparatedText)
            }
            .buttonStyle(.borderedProminent)
            Button("Export as JSON") {
                if let data = scanner.exportJSON(),
                   let json = String(data: data, encoding: .utf8) {
                    saveFile(content: json, ext: "json", type: .json)
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private func saveFile(content: String, ext: String, type: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "lan_scan.\(ext)"
        panel.allowedContentTypes = [type]
        if panel.runModal() == .OK, let url = panel.url {
            try? content.write(to: url, atomically: true, encoding: .utf8)
            dismiss()
        }
    }
}
