// LAN Scanner — CheckForUpdatesView.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import SwiftUI
import Sparkle

/// A menu-bar button that triggers a manual Sparkle update check.
///
/// Placed in the app menu via `CommandGroup(after: .appInfo)` so users
/// can check for updates from the **LAN Scanner** menu at any time.
struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel

    /// Creates the view bound to the given Sparkle updater instance.
    init(updater: SPUUpdater) {
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: viewModel.updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

/// Publishes Sparkle's `canCheckForUpdates` state so the button can
/// be disabled while an update check is already in progress.
final class CheckForUpdatesViewModel: ObservableObject {
    let updater: SPUUpdater
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        self.updater = updater
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}
