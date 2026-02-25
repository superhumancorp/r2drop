// Packages/R2Bridge/Sources/R2Bridge/UploadProgress.swift
// Upload progress model reported by the Rust engine.
// Currently consumed via SQLite polling (QueueViewModel polls bytesUploaded).
// A direct C-callback bridge can be added here in the future for
// lower-latency UI updates once the Rust FFI exposes a progress callback.

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

