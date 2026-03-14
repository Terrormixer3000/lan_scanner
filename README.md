# LAN Scanner

[![Build](https://github.com/Terrormixer3000/lan_scanner/actions/workflows/ci.yml/badge.svg)](https://github.com/Terrormixer3000/lan_scanner/actions/workflows/ci.yml)
[![Release](https://github.com/Terrormixer3000/lan_scanner/actions/workflows/release.yml/badge.svg)](https://github.com/Terrormixer3000/lan_scanner/releases)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)

A native macOS network scanner built with SwiftUI. Discover all devices on your local network, resolve hostnames, identify vendors, measure latency, and scan for open ports — all without any external dependencies.

---

## Features

- **Subnet ping sweep** — concurrent ICMP sweep to find alive hosts
- **ARP resolution** — retrieves MAC addresses from the system ARP cache
- **Hostname resolution** — DNS reverse lookups, mDNS (`.local`), and Bonjour service browsing across 16 service types
- **Vendor identification** — maps MAC address OUI prefixes to manufacturer names using the IEEE database (cached locally, auto-refreshed every 30 days)
- **Latency measurement** — per-host round-trip time from ping
- **Port scanner** — concurrent TCP scan of 27 common service ports (SSH, HTTP, HTTPS, SMB, RDP, VNC, etc.)
- **Device labelling** — assign custom labels and notes to devices, persisted across scans
- **Scan history** — stores the last 50 scan sessions with device counts and timestamps
- **Export** — save results as CSV or JSON
- **Notifications** — desktop alert when new (unlabelled) devices appear on the network
- **Resizable split-view UI** — sidebar, device table with sortable columns, and detail panel with draggable dividers
- **Auto-scan** — configurable interval-based background rescanning
- **Auto-update** — checks for new releases via [Sparkle](https://sparkle-project.org/) and installs them in-app with EdDSA signature verification

## Requirements

| Requirement | Version |
|---|---|
| macOS | 14.0 (Sonoma) or later |
| Swift | 5.9 or later |
| Xcode | 15 or later *(for local builds)* |

> **Note:** The app uses `/sbin/ping` and `/usr/sbin/arp` which require no special entitlements on macOS. No network entitlements or sandbox are required when running as a command-line tool or unsigned `.app`.

## Installation

### Download a pre-built release

1. Go to the [Releases](https://github.com/Terrormixer3000/lan_scanner/releases) page.
2. Download `LanScanner.zip` from the latest release.
3. Unzip and move `LAN Scanner.app` to your `/Applications` folder.
4. On first launch, right-click the app and choose **Open** to bypass Gatekeeper (the app is unsigned).

### Build from source

```bash
# Clone the repository
git clone https://github.com/Terrormixer3000/lan_scanner.git
cd lan_scanner

# Build in release mode
swift build -c release

# Run directly
.build/release/LanScanner
```

To build a proper `.app` bundle locally:

```bash
swift build -c release

./scripts/assemble_app.sh
open "LAN Scanner.app"
```

## Usage

1. Launch the app. The sidebar on the left shows scan stats and history.
2. Select a network interface from the **Auto** dropdown in the toolbar, or switch to **CIDR** mode and enter a custom subnet (e.g. `192.168.1.0/24`).
3. Click the **Scan** button (antenna icon) to start. A progress bar indicates scan phases:
   - Ping sweep → ARP resolution → Hostname/Bonjour resolution → Vendor lookup
4. Click a device in the table to view details on the right panel.
5. Use **Scan Ports** in the detail panel to identify open TCP ports on a device.
6. Assign a **Label** and **Notes** to a device and click **Save Label** to persist them.
7. Use the **Export** button (upload icon) to save results as CSV or JSON.

### Settings

Open **Settings** (⌘,) to configure:

- **Concurrency** — number of simultaneous ping probes (10–200)
- **Ping Timeout** — per-host timeout in seconds (0.2–3.0)
- **Auto Refresh** — enable periodic rescanning and set the interval (30–600 seconds)
- **Updates** — toggle automatic update checks and manually check for new versions

## Project Structure

```
Sources/LanScanner/
├── LanScannerApp.swift          # @main entry point and AppDelegate
├── ContentView.swift            # Root view, 3-pane resizable layout
├── Models/
│   ├── NetworkDevice.swift      # Core device data model
│   ├── NetworkInterface.swift   # Network interface descriptor
│   └── ScanSession.swift        # Historical scan snapshot
├── Services/
│   ├── NetworkScanner.swift     # Main scan orchestrator (@MainActor ObservableObject)
│   ├── PingHelper.swift         # ICMP ping sweep via /sbin/ping
│   ├── ARPResolver.swift        # ARP cache queries via /usr/sbin/arp
│   ├── HostnameResolver.swift   # DNS + mDNS reverse lookups
│   ├── BonjourResolver.swift    # Bonjour/NetServiceBrowser hostname discovery
│   ├── PortScanner.swift        # TCP port scanning via Network framework
│   ├── NetworkInterfaceManager.swift  # Active interface enumeration
│   ├── VendorLookup.swift       # IEEE OUI database for MAC → vendor mapping
│   └── Utilities.swift          # Shared concurrency primitives (Counter, LockIsolated)
└── Views/
    ├── SidebarView.swift         # Left panel: stats and scan history
    ├── DeviceListView.swift      # Centre panel: sortable/searchable device table
    ├── DeviceDetailView.swift    # Right panel: device info, port scanner, labels
    ├── ScanToolbarView.swift     # Toolbar: network selector, scan/stop, export
    ├── NetworkSelectorView.swift # Auto/CIDR network picker
    ├── ExportView.swift          # CSV/JSON export popover
    ├── CheckForUpdatesView.swift # Sparkle "Check for Updates…" menu command
    └── SettingsView.swift        # Preferences window
scripts/
└── assemble_app.sh              # Local/release .app bundle assembly with Sparkle packaging
```

## Contributing

Contributions are welcome! Here is how to get started:

1. Fork the repository.
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes and ensure `swift build` succeeds.
4. Open a pull request against `main` with a clear description of the change.

Please follow the existing code style (Swift API Design Guidelines, `///` doc comments, `@MainActor` for UI state).

## Built with Vibe Coding

This project was built using **vibe coding** — the entire codebase was developed collaboratively with AI (Claude by Anthropic & Codex by OpenAI) through natural-language prompts and iterative refinement.

## License

LAN Scanner is free software released under the **GNU General Public License v3.0**.

Copyright © 2026 Terrormixer3000

See [LICENSE](LICENSE) for the full text. In short: you are free to use, modify, and distribute this software, but any derivative work must be distributed under the same GPL-3.0 terms and include the source code.
