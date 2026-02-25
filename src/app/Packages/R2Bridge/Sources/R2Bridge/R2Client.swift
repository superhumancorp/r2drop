// Packages/R2Bridge/Sources/R2Bridge/R2Client.swift
// Swift-friendly async wrapper over the Rust C FFI.
// Each method calls the corresponding extern "C" function from r2_ffi.h,
// converts C strings to Swift strings, and handles memory cleanup.

import Foundation
import R2BridgeC

/// Swift client wrapping the Rust FFI for R2 operations.
public final class R2Client: Sendable {

    public init() {}

    // MARK: - Authentication

    /// Validate an API token against the Cloudflare API.
    /// Returns the token UUID (used as S3 Access Key ID for R2 uploads).
    public func validateToken(_ token: String) async throws -> String {
        try await Task.detached { [self] in
            #if DEBUG
            print("[R2Bridge:R2Client] validateToken begin")
            #endif
            guard let ptr = token.withCString({ r2_validate_token($0) }) else {
                #if DEBUG
                print("[R2Bridge:R2Client] validateToken failed: \(lastError())")
                #endif
                throw R2BridgeError.ffiError(lastError())
            }
            defer { r2_free_string(ptr) }
            let tokenId = String(cString: ptr)
            #if DEBUG
            print("[R2Bridge:R2Client] validateToken success tokenId=\(tokenId)")
            #endif
            return tokenId
        }.value
    }

    /// List Cloudflare accounts accessible with the given token.
    /// Returns array of dictionaries with "id" and "name" keys.
    public func listAccounts(token: String) async throws -> [[String: String]] {
        try await Task.detached { [self] in
            guard let ptr = token.withCString({ r2_list_accounts($0) }) else {
                #if DEBUG
                print("[R2Bridge:R2Client] listAccounts failed: \(lastError())")
                #endif
                throw R2BridgeError.ffiError(lastError())
            }
            defer { r2_free_string(ptr) }
            let json = String(cString: ptr)
            let accounts: [[String: String]] = try decodeJSON(json)
            #if DEBUG
            print("[R2Bridge:R2Client] listAccounts returned \(accounts.count) accounts")
            #endif
            return accounts
        }.value
    }

    /// List R2 bucket names for an account.
    public func listBuckets(accountId: String, token: String) async throws -> [String] {
        try await Task.detached { [self] in
            guard let ptr = accountId.withCString({ aid in
                token.withCString({ tok in
                    r2_list_buckets(aid, tok)
                })
            }) else {
                #if DEBUG
                print("[R2Bridge:R2Client] listBuckets failed: \(lastError())")
                #endif
                throw R2BridgeError.ffiError(lastError())
            }
            defer { r2_free_string(ptr) }
            let json = String(cString: ptr)
            let buckets: [String] = try decodeJSON(json)
            #if DEBUG
            print("[R2Bridge:R2Client] listBuckets returned \(buckets.count) buckets")
            #endif
            return buckets
        }.value
    }

    /// Create a new R2 bucket.
    public func createBucket(accountId: String, name: String, token: String) async throws {
        try await Task.detached { [self] in
            let result = accountId.withCString { aid in
                name.withCString { bname in
                    token.withCString { tok in
                        r2_create_bucket(aid, bname, tok)
                    }
                }
            }
            if result != 0 {
                throw R2BridgeError.ffiError(lastError())
            }
        }.value
    }

    // MARK: - Object Operations

    /// Check if an object exists in R2 and return its metadata (async version).
    /// Returns nil if the object does not exist. Used for conflict detection (FR-065).
    public func headObject(
        accountId: String, token: String, bucket: String, key: String
    ) async throws -> R2ObjectInfo? {
        try await Task.detached { [self] in
            #if DEBUG
            print("[R2Bridge:R2Client] headObject key=\(key)")
            #endif
            let result = try headObjectSync(accountId: accountId, token: token, bucket: bucket, key: key)
            #if DEBUG
            print("[R2Bridge:R2Client] headObject exists=\(result != nil)")
            #endif
            return result
        }.value
    }

    /// Synchronous head_object check — safe to call from any thread.
    /// The underlying FFI call blocks via Rust's block_on, so no async needed.
    /// Returns nil if the object does not exist.
    public func headObjectSync(
        accountId: String, token: String, bucket: String, key: String
    ) throws -> R2ObjectInfo? {
        guard let ptr = accountId.withCString({ aid in
            token.withCString({ tok in
                bucket.withCString({ b in
                    key.withCString({ k in
                        r2_head_object(aid, tok, b, k)
                    })
                })
            })
        }) else {
            throw R2BridgeError.ffiError(lastError())
        }
        defer { r2_free_string(ptr) }
        let json = String(cString: ptr)
        let info: R2HeadObjectResponse = try decodeJSON(json)
        guard info.exists else { return nil }
        return R2ObjectInfo(
            contentLength: info.contentLength,
            lastModified: info.lastModified,
            eTag: info.eTag
        )
    }

    // MARK: - Queue Operations

    /// Queue a file for upload. Returns the job ID.
    public func queueUpload(filePath: String, r2Key: String, bucket: String, account: String) throws -> Int64 {
        let jobId = filePath.withCString { fp in
            r2Key.withCString { key in
                bucket.withCString { b in
                    account.withCString { a in
                        r2_queue_upload(fp, key, b, a)
                    }
                }
            }
        }
        if jobId < 0 {
            #if DEBUG
            print("[R2Bridge:R2Client] queueUpload failed: \(lastError())")
            #endif
            throw R2BridgeError.ffiError(lastError())
        }
        #if DEBUG
        print("[R2Bridge:R2Client] queueUpload filePath=\(filePath) jobId=\(jobId)")
        #endif
        return jobId
    }

    /// Pause an upload job.
    public func pauseUpload(id: Int64) throws {
        if r2_pause_upload(id) != 0 {
            throw R2BridgeError.ffiError(lastError())
        }
    }

    /// Resume a paused upload job.
    public func resumeUpload(id: Int64) throws {
        if r2_resume_upload(id) != 0 {
            throw R2BridgeError.ffiError(lastError())
        }
    }

    /// Cancel an upload job.
    public func cancelUpload(id: Int64) throws {
        if r2_cancel_upload(id) != 0 {
            throw R2BridgeError.ffiError(lastError())
        }
    }

    /// Get current queue status as JSON string (to be decoded by caller).
    public func getQueueStatus() throws -> String {
        guard let ptr = r2_get_queue_status() else {
            throw R2BridgeError.ffiError(lastError())
        }
        defer { r2_free_string(ptr) }
        return String(cString: ptr)
    }

    /// Get upload history as JSON string (to be decoded by caller).
    public func getHistory() throws -> String {
        guard let ptr = r2_get_history() else {
            throw R2BridgeError.ffiError(lastError())
        }
        defer { r2_free_string(ptr) }
        return String(cString: ptr)
    }

    // MARK: - Queue Processing

    /// Process pending upload jobs for a specific account.
    /// Uses S3-compatible credentials (access_key_id, secret_access_key) for R2 uploads.
    /// The access_key_id is the token UUID, secret_access_key is SHA-256(api_token).
    /// Returns the number of jobs completed.
    public func processQueue(
        accountId: String, accessKeyId: String, secretAccessKey: String, accountName: String
    ) throws -> Int32 {
        let result = accountId.withCString { aid in
            accessKeyId.withCString { akid in
                secretAccessKey.withCString { sak in
                    accountName.withCString { name in
                        r2_process_queue(aid, akid, sak, name)
                    }
                }
            }
        }
        if result < 0 {
            #if DEBUG
            print("[R2Bridge:R2Client] processQueue failed: \(lastError())")
            #endif
            throw R2BridgeError.ffiError(lastError())
        }
        #if DEBUG
        if result > 0 {
            print("[R2Bridge:R2Client] processQueue completed=\(result)")
        }
        #endif
        return result
    }


    // MARK: - Network Status (FR-031)

    /// Inform the Rust engine about network connectivity changes.
    /// Called when NWPathMonitor detects a network connectivity transition.
    public func setNetworkAvailable(_ available: Bool) {
        #if DEBUG
        print("[R2Bridge:R2Client] setNetworkAvailable=\(available)")
        #endif
        r2_set_network_available(available)
    }

    // MARK: - Logging (FR-067)

    /// Initialize the Rust audit logging system.
    /// Call once at app startup. Subsequent calls are no-ops.
    /// Returns 0 on success, -1 on error.
    @discardableResult
    public static func initLogging(maxLogFiles: UInt16, maxLogFileSizeMb: UInt16) -> Int32 {
        r2_init_logging(maxLogFiles, maxLogFileSizeMb)
    }

    // MARK: - Helpers

    /// Read the last error message from the FFI layer.
    private func lastError() -> String {
        guard let ptr = r2_get_last_error() else {
            return "Unknown FFI error"
        }
        defer { r2_free_string(ptr) }
        return String(cString: ptr)
    }

    /// Decode a JSON string into the specified type.
    private func decodeJSON<T: Decodable>(_ json: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw R2BridgeError.invalidJSON("Failed to encode JSON string as UTF-8")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw R2BridgeError.invalidJSON(error.localizedDescription)
        }
    }
}

// MARK: - Object Info Types

/// Metadata about an existing R2 object. Returned by headObject().
public struct R2ObjectInfo: Sendable {
    /// Object size in bytes (nil if unavailable).
    public let contentLength: UInt64?
    /// Last modification as epoch seconds string (nil if unavailable).
    public let lastModified: String?
    /// S3 ETag value.
    public let eTag: String?

    /// Last modification as a Date, or nil if not available.
    public var lastModifiedDate: Date? {
        guard let str = lastModified, let secs = Double(str) else { return nil }
        return Date(timeIntervalSince1970: secs)
    }
}

/// Internal JSON response shape from r2_head_object FFI.
private struct R2HeadObjectResponse: Decodable {
    let exists: Bool
    let contentLength: UInt64?
    let lastModified: String?
    let eTag: String?

    enum CodingKeys: String, CodingKey {
        case exists
        case contentLength = "content_length"
        case lastModified = "last_modified"
        case eTag = "e_tag"
    }
}
