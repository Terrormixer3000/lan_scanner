// LAN Scanner — VendorLookup.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import Foundation

/// Maps MAC address OUI prefixes to manufacturer names using the IEEE public database.
///
/// `VendorLookup` is a singleton that downloads the IEEE OUI, CID, and MAM assignment
/// files on first use and caches the parsed results as JSON in
/// `~/Library/Application Support/LanScanner/mac-vendors.json`. The cache is
/// automatically refreshed in the background when it is older than 30 days.
///
/// All public methods are thread-safe via `NSLock`.
final class VendorLookup: @unchecked Sendable {
    /// The shared singleton instance.
    static let shared = VendorLookup()

    private let lock = NSLock()
    private var prefixes: [Int: [String: String]] = [:]
    private var prepareTask: Task<Void, Never>?

    private init() {
        loadCachedPrefixes()
    }

    /// Ensures the vendor database is loaded, downloading it if necessary.
    ///
    /// Call this once at app startup (or before the first call to `lookup(mac:)`).
    /// If a cached database already exists, this returns immediately and triggers
    /// a background refresh only when the cache is stale (>30 days old).
    func prepare() async {
        if hasPrefixes {
            refreshIfNeededInBackground()
            return
        }

        let task = lock.withLock {
            if let prepareTask {
                return prepareTask
            }

            let task = Task { [weak self] in
                guard let self else { return }
                defer {
                    self.lock.withLock {
                        self.prepareTask = nil
                    }
                }
                await self.downloadAndCachePrefixes()
            }
            prepareTask = task
            return task
        }

        await task.value
    }

    /// Looks up the manufacturer name for a given MAC address.
    ///
    /// Tries prefix lengths of 9, 7, and 6 hexadecimal characters (corresponding to
    /// OUI-36, OUI-28/MAM, and OUI-24 registries respectively), matching the longest
    /// prefix first.
    ///
    /// - Parameter mac: A MAC address in any common format (colons, dashes, or raw hex).
    /// - Returns: The vendor name string, or `nil` if no match was found.
    func lookup(mac: String) -> String? {
        let normalized = normalize(mac: mac)
        guard normalized.count >= 6 else { return nil }

        let currentPrefixes = lock.withLock { prefixes }
        for prefixLength in [9, 7, 6] where normalized.count >= prefixLength {
            let prefix = String(normalized.prefix(prefixLength))
            if let vendor = currentPrefixes[prefixLength]?[prefix] {
                return vendor
            }
        }

        return nil
    }

    private var hasPrefixes: Bool {
        lock.withLock { !prefixes.isEmpty }
    }

    private func refreshIfNeededInBackground() {
        guard shouldRefreshCache else { return }

        lock.withLock {
            guard prepareTask == nil else { return }
            prepareTask = Task { [weak self] in
                guard let self else { return }
                defer {
                    self.lock.withLock {
                        self.prepareTask = nil
                    }
                }
                await self.downloadAndCachePrefixes()
            }
        }
    }

    private var vendorCacheDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LanScanner", isDirectory: true)
    }

    private var vendorCacheURL: URL {
        vendorCacheDirectory.appendingPathComponent("mac-vendors.json")
    }

    private var shouldRefreshCache: Bool {
        guard
            let values = try? vendorCacheURL.resourceValues(forKeys: [.contentModificationDateKey]),
            let modifiedAt = values.contentModificationDate
        else {
            return true
        }

        return modifiedAt < Date().addingTimeInterval(-30 * 24 * 60 * 60)
    }

    private func loadCachedPrefixes() {
        guard
            let data = try? Data(contentsOf: vendorCacheURL),
            let cache = try? JSONDecoder().decode(VendorCache.self, from: data)
        else {
            return
        }

        lock.withLock {
            prefixes = cache.prefixesByLength.reduce(into: [:]) { partialResult, item in
                partialResult[item.key] = item.value
            }
        }
    }

    private func saveCachedPrefixes(_ prefixes: [Int: [String: String]]) {
        try? FileManager.default.createDirectory(at: vendorCacheDirectory, withIntermediateDirectories: true)
        let cache = VendorCache(prefixesByLength: prefixes)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: vendorCacheURL, options: .atomic)
    }

    private func downloadAndCachePrefixes() async {
        let sources: [(url: URL, prefixLength: Int, overwriteExisting: Bool)] = [
            (URL(string: "https://standards-oui.ieee.org/oui/oui.csv")!, 6, true),
            (URL(string: "https://standards-oui.ieee.org/cid/cid.csv")!, 6, false),
            (URL(string: "https://standards-oui.ieee.org/oui28/mam.csv")!, 7, true),
            (URL(string: "https://standards-oui.ieee.org/oui36/oui36.csv")!, 9, true)
        ]

        do {
            var loadedPrefixes: [Int: [String: String]] = [:]

            for source in sources {
                let (data, _) = try await URLSession.shared.data(from: source.url)
                let parsed = parseAssignments(from: data, prefixLength: source.prefixLength)
                var bucket = loadedPrefixes[source.prefixLength] ?? [:]

                for (prefix, vendor) in parsed {
                    if source.overwriteExisting || bucket[prefix] == nil {
                        bucket[prefix] = vendor
                    }
                }

                loadedPrefixes[source.prefixLength] = bucket
            }

            guard !loadedPrefixes.isEmpty else { return }

            lock.withLock {
                prefixes = loadedPrefixes
            }
            saveCachedPrefixes(loadedPrefixes)
        } catch {
            if !hasPrefixes {
                return
            }
        }
    }

    private func parseAssignments(from data: Data, prefixLength: Int) -> [String: String] {
        guard let text = String(data: data, encoding: .utf8) else { return [:] }

        var parsed: [String: String] = [:]
        text.enumerateLines { line, _ in
            let columns = CSVLineParser.parse(line)
            guard columns.count >= 3 else { return }

            let assignment = columns[1]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            let vendor = columns[2].trimmingCharacters(in: .whitespacesAndNewlines)

            guard assignment.count == prefixLength, !vendor.isEmpty else { return }
            parsed[assignment] = vendor
        }

        return parsed
    }

    private func normalize(mac: String) -> String {
        mac.unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

private struct VendorCache: Codable {
    let prefixesByLength: [Int: [String: String]]
}

private enum CSVLineParser {
    static func parse(_ line: String) -> [String] {
        var columns: [String] = []
        var current = ""
        var isInsideQuotes = false

        for character in line {
            switch character {
            case "\"":
                isInsideQuotes.toggle()
            case "," where !isInsideQuotes:
                columns.append(current)
                current.removeAll(keepingCapacity: true)
            default:
                current.append(character)
            }
        }

        columns.append(current)
        return columns
    }
}

private extension NSLock {
    func withLock<T>(_ action: () -> T) -> T {
        lock()
        defer { unlock() }
        return action()
    }
}
