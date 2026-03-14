// LAN Scanner — LanScannerApp.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import SwiftUI

/// The top-level SwiftUI application entry point.
///
/// Declares two scenes:
/// - A `WindowGroup` hosting `ContentView`, which pre-loads the vendor database on first launch.
/// - A `Settings` scene bound to `SettingsView` (accessible via ⌘,).
@main
struct LanScannerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await VendorLookup.shared.prepare()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentSize)
        .defaultSize(width: 1200, height: 800)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        
        Settings {
            SettingsView()
        }
    }
}
/// `NSApplicationDelegate` that ensures the application window comes to the foreground on launch
/// and re-activates when the user clicks the Dock icon while the app is already running.
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Bring the app to the foreground and keep it there
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Ensure the main window is visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApp.windows.first {
                window.makeKeyAndOrderFront(nil)
                window.setIsVisible(true)
            }
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        for window in sender.windows {
            window.makeKeyAndOrderFront(self)
            window.setIsVisible(true)
        }
        return true
    }
}
