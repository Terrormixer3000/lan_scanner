// LAN Scanner — ContentView.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import SwiftUI
import UserNotifications

/// The root view of the application.
///
/// Owns the `NetworkScanner` state object and composes:
/// - A `ResizableSplitView` with sidebar, device table, and optional detail panel.
/// - A `LoadingOverlay` shown while a scan is active.
/// - A `StatusFooterView` pinned to the bottom showing scan progress and device count.
struct ContentView: View {
    @StateObject private var scanner = NetworkScanner()
    @State private var selectedDevice: NetworkDevice?
    @State private var showExport = false
    @State private var searchText = ""
    @State private var showsDetails = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ResizableSplitView(
                    scanner: scanner,
                    selectedDevice: $selectedDevice,
                    searchText: $searchText,
                    showExport: $showExport,
                    showsDetails: $showsDetails
                )

                if scanner.isScanning {
                    LoadingOverlay(
                        progress: scanner.progress,
                        statusMessage: scanner.statusMessage
                    )
                }
            }

            StatusFooterView(scanner: scanner)
        }
        .onAppear {
            requestNotificationPermissions()
        }
        .onChange(of: scanner.devices) { _, devices in
            guard let selectedDevice else { return }
            self.selectedDevice = devices.first(where: { $0.id == selectedDevice.id })
        }
    }
    
    private func requestNotificationPermissions() {
        guard AppRuntime.canUseUserNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}

/// Status bar shown at the bottom of the window.
///
/// Displays the current `statusMessage` on the left. While scanning, a linear
/// progress indicator and percentage are shown on the right. When idle, it shows
/// the total device count.
struct StatusFooterView: View {
    @ObservedObject var scanner: NetworkScanner

    var body: some View {
        HStack(spacing: 12) {
            Text(scanner.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if scanner.isScanning {
                ProgressView(value: scanner.progress)
                    .controlSize(.small)
                    .frame(width: 100)
                    .progressViewStyle(.linear)

                Text("\(Int(scanner.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("\(scanner.devices.count) device(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

// MARK: - Resizable Split View

/// Three-pane layout with user-draggable dividers between sidebar, device list, and detail panel.
///
/// Pane widths are stored in local `@State` and bounded by minimum/maximum constraints
/// derived from the available `GeometryReader` width.
struct ResizableSplitView: View {
    @ObservedObject var scanner: NetworkScanner
    @Binding var selectedDevice: NetworkDevice?
    @Binding var searchText: String
    @Binding var showExport: Bool
    @Binding var showsDetails: Bool
    
    @State private var sidebarWidth: CGFloat = 220
    @State private var listWidth: CGFloat = 600
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Sidebar
                SidebarView(scanner: scanner)
                    .frame(width: sidebarWidth)
                
        // Erste Divider (Sidebar <-> Liste)
                DividerHandle(
                    width: $sidebarWidth,
                    minWidth: 180,
                    maxWidth: min(400, geometry.size.width * 0.4)
                )
                
                // Device Liste
                VStack(spacing: 0) {
                    DeviceListView(
                        scanner: scanner,
                        selectedDevice: $selectedDevice,
                        searchText: $searchText
                    )
                    .searchable(text: $searchText, prompt: "Search devices...")
                }
                .frame(width: showsDetails ? listWidth : nil)
                .frame(maxWidth: showsDetails ? nil : .infinity)
                .toolbar {
                    ScanToolbarView(
                        scanner: scanner,
                        showExport: $showExport,
                        showsDetails: $showsDetails
                    )
                }

                if showsDetails {
                    DividerHandle(
                        width: $listWidth,
                        minWidth: 300,
                        maxWidth: geometry.size.width - sidebarWidth - 300 - 20
                    )

                    Group {
                        if let device = selectedDevice {
                            DeviceDetailView(device: device, scanner: scanner)
                        } else {
                            ContentUnavailableView(
                                "Select a Device",
                                systemImage: "network",
                                description: Text("Select a device from the list to see details")
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Divider Handle

/// An interactive drag handle that resizes an adjacent pane.
///
/// The handle has an invisible 10-point wide hit area for easier interaction,
/// a 1-point separator line, and a highlighted accent bar while the cursor is hovering.
/// It sets the `resizeLeftRight` cursor on hover.
struct DividerHandle: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    
    @State private var isHovering = false
    @State private var startWidth: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Invisible wide hit-area for easier grab
            Color.clear
                .frame(width: 10)
                .contentShape(Rectangle())
            
            // Visible 1px separator line
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
            
            // Accent highlight while hovering
            if isHovering {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: 3)
            }
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                DispatchQueue.main.async {
                    NSCursor.resizeLeftRight.set()
                }
            } else {
                DispatchQueue.main.async {
                    NSCursor.arrow.set()
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if startWidth == 0 {
                        startWidth = width
                    }
                    let newWidth = startWidth + value.translation.width
                    width = min(max(newWidth, minWidth), maxWidth)
                }
                .onEnded { _ in
                    startWidth = 0
                }
        )
    }
}

// MARK: - Ladeanimation Overlay
struct LoadingOverlay: View {
    let progress: Double
    let statusMessage: String
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.12))
                .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Scanning Network")
                            .font(.headline)

                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    Text("\(Int(progress * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: progress, total: 1.0)
                    .controlSize(.small)
                    .progressViewStyle(.linear)
            }
            .frame(width: 320)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.18))
            }
            .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
        }
        .transition(.opacity)
        .animation(.easeInOut, value: progress)
    }
}
