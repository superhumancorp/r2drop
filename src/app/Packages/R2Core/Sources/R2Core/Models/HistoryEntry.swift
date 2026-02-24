// Packages/R2Core/Sources/R2Core/Models/HistoryEntry.swift
// Represents a completed upload stored in the history database.

import Foundation

/// A completed upload record from the history database.
public struct HistoryEntry: Codable, Identifiable, Equatable {
    public var id: Int64
    public var fileName: String
    public var fileSize: UInt64
    public var r2Key: String
    public var bucket: String
    public var accountName: String
    public var url: String
    public var uploadedAt: String

    public init(
        id: Int64,
        fileName: String,
        fileSize: UInt64,
        r2Key: String,
        bucket: String,
        accountName: String,
        url: String,
        uploadedAt: String
    ) {
        self.id = id
        self.fileName = fileName
        self.fileSize = fileSize
        self.r2Key = r2Key
        self.bucket = bucket
        self.accountName = accountName
        self.url = url
        self.uploadedAt = uploadedAt
    }
}
