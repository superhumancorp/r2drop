// Packages/R2Bridge/Sources/R2Bridge/R2BridgeError.swift
// Error types for the R2Bridge FFI wrapper.

import Foundation

/// Errors from the Rust FFI bridge.
public enum R2BridgeError: LocalizedError {
    case ffiError(String)
    case nullPointer
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .ffiError(let msg): return "R2 FFI error: \(msg)"
        case .nullPointer: return "R2 FFI returned null unexpectedly"
        case .invalidJSON(let msg): return "Invalid JSON from FFI: \(msg)"
        }
    }
}
