// Packages/R2Core/Sources/R2Core/Models/UploadJob.swift
// Represents a single upload job in the persistent queue.

import Foundation

/// Status of an upload job in the queue.
public enum UploadStatus: String, Codable {
    case pending
    case uploading
    case paused
    case completed
    case failed
}

/// A single upload job tracked in the SQLite queue.
public struct UploadJob: Codable, Identifiable, Equatable {
    public var id: Int64
    public var filePath: String
    public var r2Key: String
    public var bucket: String
    public var accountName: String
    public var status: UploadStatus
    public var bytesUploaded: UInt64
    public var totalBytes: UInt64
    public var uploadId: String?
    public var errorMessage: String?
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: Int64,
        filePath: String,
        r2Key: String,
        bucket: String,
        accountName: String,
        status: UploadStatus = .pending,
        bytesUploaded: UInt64 = 0,
        totalBytes: UInt64 = 0,
        uploadId: String? = nil,
        errorMessage: String? = nil,
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.id = id
        self.filePath = filePath
        self.r2Key = r2Key
        self.bucket = bucket
        self.accountName = accountName
        self.status = status
        self.bytesUploaded = bytesUploaded
        self.totalBytes = totalBytes
        self.uploadId = uploadId
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Progress as a fraction from 0.0 to 1.0.
    public var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesUploaded) / Double(totalBytes)
    }
}
