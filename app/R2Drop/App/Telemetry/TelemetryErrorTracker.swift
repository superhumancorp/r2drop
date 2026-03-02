// R2Drop/App/Telemetry/TelemetryErrorTracker.swift
// Captures errors with anti-spam: first occurrence emitted immediately as `app_error`,
// repeated identical errors within 5 minutes are aggregated and flushed as
// `app_error_summary` every 60 seconds or on app termination.
// Dedupe key: component + operation + error_domain + error_code + error_message_hash.

import Foundation

// MARK: - ErrorContext

/// Metadata for a captured error — used for grouping and deduplication.
struct ErrorContext {
    let component: String      // e.g. "onboarding", "upload_processor", "finder_queue_bridge"
    let operation: String      // e.g. "validate_token", "process_queue", "transfer_job"
    let userVisible: Bool      // Was this shown to the user?
    let recoverable: Bool      // Can the user retry?
    let entrypoint: String?    // Upload entrypoint, if relevant
}

// MARK: - TelemetryErrorTracker

/// Tracks errors with spam prevention. First occurrence → immediate `app_error` event.
/// Repeats within 5 minutes → aggregated and flushed as `app_error_summary` every 60s.
@MainActor
final class TelemetryErrorTracker {

    /// Callback to emit an event. Set by TelemetryService on init.
    var emitEvent: ((_ event: String, _ properties: [String: Any]) -> Void)?

    /// Aggregated error counts waiting for flush.
    private var aggregated: [String: AggregatedError] = [:]

    /// Timer for periodic summary flush.
    private var flushTimer: Timer?

    /// Flush interval: 60 seconds.
    private static let flushInterval: TimeInterval = 60

    /// Rate limiter for first-occurrence dedup.
    private let rateLimiter = TelemetryRateLimiter()

    // MARK: - Aggregated Error State

    private struct AggregatedError {
        let component: String
        let operation: String
        let errorType: String
        let errorCode: String
        var repeatCount: Int
        let firstSeenDate: Date
        var lastSeenDate: Date
    }

    // MARK: - Lifecycle

    /// Start the periodic flush timer.
    func start() {
        guard flushTimer == nil else { return }
        flushTimer = Timer.scheduledTimer(
            withTimeInterval: Self.flushInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
    }

    /// Stop the timer and flush remaining summaries.
    func stop() {
        flush()
        flushTimer?.invalidate()
        flushTimer = nil
    }

    // MARK: - Capture

    /// Record an error. First occurrence per dedupe window → emits `app_error`.
    /// Subsequent identical errors → aggregated for summary flush.
    func captureError(_ error: Error, context: ErrorContext) {
        let nsError = error as NSError
        let errorType = String(describing: type(of: error))
        let errorDomain = nsError.domain
        let errorCode = String(nsError.code)
        let messageHash = TelemetrySanitizer.errorHash(error.localizedDescription)

        let dedupeKey = "\(context.component):\(context.operation):\(errorDomain):\(errorCode):\(messageHash)"

        if rateLimiter.shouldSend(key: dedupeKey) {
            // First occurrence — emit immediately
            var props: [String: Any] = [
                "component": context.component,
                "operation": context.operation,
                "error_type": errorType,
                "error_domain": errorDomain,
                "error_code": errorCode,
                "error_message_hash": messageHash,
                "user_visible": context.userVisible,
                "recoverable": context.recoverable,
                "dedupe_key": dedupeKey
            ]
            if let entrypoint = context.entrypoint {
                props["entrypoint"] = entrypoint
            }
            emitEvent?("app_error", props)
        } else {
            // Subsequent occurrence — aggregate for summary
            let now = Date()
            if var existing = aggregated[dedupeKey] {
                existing.repeatCount += 1
                existing.lastSeenDate = now
                aggregated[dedupeKey] = existing
            } else {
                aggregated[dedupeKey] = AggregatedError(
                    component: context.component,
                    operation: context.operation,
                    errorType: errorType,
                    errorCode: errorCode,
                    repeatCount: 1,
                    firstSeenDate: now,
                    lastSeenDate: now
                )
            }
        }
    }

    // MARK: - Flush

    /// Emit `app_error_summary` events for all aggregated errors, then clear.
    func flush() {
        let sessionStart = TelemetryService.shared.sessionStartTime
        for (_, agg) in aggregated where agg.repeatCount > 0 {
            let props: [String: Any] = [
                "window_sec": Self.flushInterval,
                "component": agg.component,
                "operation": agg.operation,
                "error_type": agg.errorType,
                "error_code": agg.errorCode,
                "repeat_count": agg.repeatCount,
                "first_seen_offset_ms": Int(agg.firstSeenDate.timeIntervalSince(sessionStart) * 1000),
                "last_seen_offset_ms": Int(agg.lastSeenDate.timeIntervalSince(sessionStart) * 1000)
            ]
            emitEvent?("app_error_summary", props)
        }
        aggregated.removeAll()
        rateLimiter.prune()
    }
}
