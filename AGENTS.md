# AGENTS.md — LAN Scanner

Guidelines for AI agents working on this codebase.

## Project Overview

LAN Scanner is a native macOS network scanner built with SwiftUI and Swift Package Manager. It discovers devices on a local subnet via ICMP ping sweep, resolves hostnames (DNS, mDNS, Bonjour), identifies vendors from IEEE OUI data, measures latency, and scans TCP ports. The app is distributed as an unsigned `.app` bundle via GitHub Releases.

## Architecture

- **Entry point:** `LanScannerApp.swift` — `@main` SwiftUI app with `NSApplicationDelegate`
- **Services layer:** `Sources/LanScanner/Services/` — each service is a focused actor or class handling one responsibility (ping, ARP, hostname, vendor lookup, port scan, updates)
- **Views layer:** `Sources/LanScanner/Views/` — SwiftUI views for the 3-pane layout, settings, and update UI
- **Models:** `Sources/LanScanner/Models/` — lightweight data models (`NetworkDevice`, `NetworkInterface`, `ScanSession`)
- **Auto-update:** Sparkle framework via SPM. Appcast hosted on `main` branch, EdDSA-signed releases.

## Code Conventions

- Follow **Swift API Design Guidelines**
- Use `///` doc comments on all public types, methods, and properties
- Use `@MainActor` for UI-related state and `ObservableObject` classes
- Code comments and doc comments in **English**
- Copyright header on every Swift file: `// LAN Scanner — <FileName>.swift` + `// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.`
- No unnecessary abstractions — keep it simple and direct

## Dependencies

- **Sparkle** (SPM) — auto-update framework. Only external dependency.
- Everything else uses Foundation/AppKit/SwiftUI/Network frameworks from macOS SDK.
- Do **not** add new external dependencies without explicit approval.

## Build & Run

```bash
# Build
swift build -c release

# Run directly
.build/release/LanScanner

# Build .app bundle locally
swift build -c release
mkdir -p "LAN Scanner.app/Contents/MacOS"
cp .build/release/LanScanner "LAN Scanner.app/Contents/MacOS/"
cp Sources/LanScanner/Info.plist "LAN Scanner.app/Contents/"
open "LAN Scanner.app"
```

## Release Process

1. Tag a commit: `git tag v1.x.x && git push origin main --tags`
2. GitHub Actions (`release.yml`) builds the `.app`, signs the ZIP with Sparkle's EdDSA key, updates `appcast.xml`, and creates a GitHub Release.
3. The `SPARKLE_PRIVATE_KEY` secret must be configured in GitHub Actions.

## Patterns to Reuse

- **URLSession downloads with caching:** See `VendorLookup.swift` — async/await download, local file cache in `~/Library/Application Support/LanScanner/`
- **Process execution:** See `PingHelper.swift`, `ARPResolver.swift` — running CLI tools via `Process()` with async wrappers
- **@AppStorage preferences:** See `SettingsView.swift` — persistent user settings via `@AppStorage`
- **Sparkle integration:** See `LanScannerApp.swift`, `CheckForUpdatesView.swift` — updater controller setup and menu command

## Important Notes

- The app is **unsigned** — Sparkle uses `SUEnableInstallerLauncherService=false` and relies on EdDSA signatures only
- Target platform is **macOS 14.0+** (Sonoma)
- Keep the `README.md` and project structure section up to date when adding/removing files
- The `Info.plist` version (`CFBundleShortVersionString`) is overwritten at release time by the CI workflow from the git tag
