// LAN Scanner — Utilities.swift
// Copyright © 2026 Terrormixer3000. Licensed under GPL-3.0.

import Foundation

/// A thread-safe integer counter for tracking completed tasks across concurrent child tasks.
///
/// Each call to `increment()` atomically increases the value and returns the new count,
/// making it safe to call from multiple Swift concurrency tasks without data races.
actor Counter {
    private var value: Int = 0
    /// Increments the counter by one and returns the updated value.
    func increment() -> Int {
        value += 1
        return value
    }
}

/// A generic, `Sendable`-conforming wrapper that protects a value with an `NSLock`.
///
/// Use this when you need to mutate a value from within a closure or non-async context
/// where Swift actors are not available (e.g. `DispatchQueue` callbacks or `NWConnection`
/// state update handlers).
final class LockIsolated<Value>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()

    init(_ value: Value) { self._value = value }

    /// Acquires the lock, executes `work` with an `inout` reference to the protected value,
    /// and releases the lock before returning the result.
    @discardableResult
    func withLock<T>(_ work: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return work(&_value)
    }
}

/// Provides runtime information about the application bundle context.
enum AppRuntime {
    /// `true` when the process is running inside a proper `.app` bundle with a bundle identifier.
    ///
    /// Used to guard `UNUserNotificationCenter` usage, which requires an app bundle context and
    /// crashes when called from a plain command-line executable.
    static var canUseUserNotifications: Bool {
        let bundleURL = Bundle.main.bundleURL
        return bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }
}
