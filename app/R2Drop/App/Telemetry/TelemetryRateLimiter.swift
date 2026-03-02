// R2Drop/App/Telemetry/TelemetryRateLimiter.swift
// Deduplicates repeated events by key + time window.
// Default window is 5 minutes — identical events within this window are suppressed.
// Thread-safe for MainActor usage (all telemetry calls are @MainActor).

import Foundation

// MARK: - TelemetryRateLimiter

/// Prevents event spam by suppressing duplicate events within a time window.
/// Each event is identified by a dedupe key (e.g. "component:operation:error_code").
/// The first occurrence passes through; subsequent identical events within the window
/// are suppressed and counted for later summary emission.
@MainActor
final class TelemetryRateLimiter {

    /// Default suppression window: 5 minutes.
    nonisolated static let defaultWindowSeconds: TimeInterval = 300

    /// Tracks when each dedupe key was last emitted.
    private var lastEmitted: [String: Date] = [:]

    /// Counts suppressed occurrences per key for summary reporting.
    private(set) var suppressedCounts: [String: Int] = [:]

    // MARK: - Public API

    /// Check if an event with the given key should be sent.
    /// Returns true if the event should be emitted (first occurrence or window expired).
    /// Returns false if it should be suppressed (duplicate within window).
    func shouldSend(key: String, windowSeconds: TimeInterval = defaultWindowSeconds) -> Bool {
        let now = Date()

        if let last = lastEmitted[key] {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < windowSeconds {
                // Still within suppression window — count and suppress
                suppressedCounts[key, default: 0] += 1
                return false
            }
        }

        // First occurrence or window expired — allow through
        lastEmitted[key] = now
        suppressedCounts.removeValue(forKey: key)
        return true
    }

    /// Reset a specific key's rate limit (e.g. after flushing summary).
    func reset(key: String) {
        lastEmitted.removeValue(forKey: key)
        suppressedCounts.removeValue(forKey: key)
    }

    /// Reset all rate limits.
    func resetAll() {
        lastEmitted.removeAll()
        suppressedCounts.removeAll()
    }

    /// Remove expired entries to prevent unbounded growth.
    /// Call periodically (e.g. every few minutes).
    func prune(windowSeconds: TimeInterval = defaultWindowSeconds) {
        let now = Date()
        let expiredKeys = lastEmitted.filter { now.timeIntervalSince($0.value) >= windowSeconds }.map(\.key)
        for key in expiredKeys {
            lastEmitted.removeValue(forKey: key)
            suppressedCounts.removeValue(forKey: key)
        }
    }
}
