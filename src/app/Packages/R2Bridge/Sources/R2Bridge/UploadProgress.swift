// Packages/R2Bridge/Sources/R2Bridge/UploadProgress.swift
// Upload progress model and bridge from Rust C callback to Swift AsyncStream.
//
// The Rust FFI reports progress via a C function pointer (R2ProgressCallback).
// ProgressBridge converts this into a Swift AsyncStream<UploadProgress> so
// SwiftUI views can consume real-time progress using async/await.

import Foundation
import R2BridgeC

// MARK: - Upload Progress Model

/// Real-time upload progress reported by the Rust engine.
public struct UploadProgress: Sendable {
    /// Number of bytes uploaded so far.
    public let bytesUploaded: UInt64
    /// Total file size in bytes.
    public let totalBytes: UInt64
    /// Current upload speed in bytes per second.
    public let speedBytesPerSecond: Double
    /// Estimated time remaining in seconds.
    public let etaSeconds: Double

    /// Progress fraction from 0.0 to 1.0.
    public var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesUploaded) / Double(totalBytes)
    }

    /// True when the upload has finished (all bytes transferred).
    public var isComplete: Bool {
        totalBytes > 0 && bytesUploaded >= totalBytes
    }
}

// MARK: - Progress Bridge
//
// NOTE: ProgressBridge and cCallback are currently not wired into any upload path.
// Progress currently flows through queue.db polling (QueueViewModel polls bytesUploaded).
// This infrastructure is reserved for future direct-callback progress reporting,
// which would bypass SQLite polling for lower-latency UI updates.

/// Bridges the C function pointer progress callback from Rust FFI
/// to a Swift `AsyncStream<UploadProgress>`.
///
/// Only one progress stream can be active at a time. Creating a new stream
/// automatically finishes the previous one.
///
/// Usage:
/// ```swift
/// let (stream, callback) = ProgressBridge.makeStream()
/// // Pass `callback` to an FFI function that accepts R2ProgressCallback
/// for await progress in stream {
///     print("Progress: \(progress.fraction * 100)%")
/// }
/// ```
public enum ProgressBridge {

    // Lock protects the shared continuation. Thread-safe for concurrent
    // FFI callbacks arriving from Rust's tokio threads.
    private static let lock = NSLock()
    private static var continuation: AsyncStream<UploadProgress>.Continuation?

    /// Create a new progress stream and C function pointer.
    ///
    /// Returns a tuple of:
    /// - `AsyncStream<UploadProgress>` to consume in Swift
    /// - `R2ProgressCallback` (C function pointer) to pass to the FFI layer
    ///
    /// Creating a new stream finishes any previously active stream.
    public static func makeStream() -> (AsyncStream<UploadProgress>, R2ProgressCallback) {
        lock.lock()
        // Finish any previously active stream
        continuation?.finish()

        var captured: AsyncStream<UploadProgress>.Continuation!
        let stream = AsyncStream<UploadProgress> { cont in
            captured = cont
        }
        continuation = captured
        lock.unlock()

        return (stream, cCallback)
    }

    /// Finish the current progress stream.
    /// Call this when the upload completes, fails, or is cancelled.
    public static func finish() {
        lock.lock()
        continuation?.finish()
        continuation = nil
        lock.unlock()
    }

    /// Yield a progress update to the active stream (if any).
    /// Called from the C callback handler. Thread-safe.
    fileprivate static func yield(_ progress: UploadProgress) {
        lock.lock()
        continuation?.yield(progress)
        lock.unlock()
    }
}

// MARK: - C Callback

/// Non-capturing closure matching the R2ProgressCallback C typedef.
/// This is the function pointer passed to Rust FFI functions.
///
/// Because C function pointers cannot capture context, this uses
/// the ProgressBridge static storage to forward values to the
/// active AsyncStream continuation.
private let cCallback: @convention(c) (UInt64, UInt64, Double, Double) -> Void = {
    bytesUploaded, totalBytes, speedBps, etaSecs in
    ProgressBridge.yield(UploadProgress(
        bytesUploaded: bytesUploaded,
        totalBytes: totalBytes,
        speedBytesPerSecond: speedBps,
        etaSeconds: etaSecs
    ))
}
