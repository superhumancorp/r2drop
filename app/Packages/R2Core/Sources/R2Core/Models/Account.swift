// Packages/R2Core/Sources/R2Core/Models/Account.swift
// Represents a Cloudflare R2 account with bucket and path configuration.

import Foundation

/// A configured Cloudflare account for R2 uploads.
public struct Account: Codable, Identifiable, Equatable {
    public var id: String { name }
    public var name: String
    public var bucket: String
    public var defaultPath: String
    public var customDomain: String?
    public var accountId: String

    public init(
        name: String,
        bucket: String = "",
        defaultPath: String = "",
        customDomain: String? = nil,
        accountId: String = ""
    ) {
        self.name = name
        self.bucket = bucket
        self.defaultPath = defaultPath
        self.customDomain = customDomain
        self.accountId = accountId
    }
}
