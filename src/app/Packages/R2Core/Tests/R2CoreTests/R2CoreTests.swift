// Tests/R2CoreTests/R2CoreTests.swift
// Tests for R2Core models and data managers.

import XCTest
@testable import R2Core

final class R2CoreTests: XCTestCase {

    // MARK: - Model Tests

    func testAccountIdentity() {
        let account = Account(name: "test", bucket: "my-bucket", accountId: "abc123")
        XCTAssertEqual(account.id, "test")
        XCTAssertEqual(account.bucket, "my-bucket")
    }

    func testUploadJobProgress() {
        var job = UploadJob(
            id: 1, filePath: "/tmp/test.txt", r2Key: "test.txt",
            bucket: "b", accountName: "a", totalBytes: 100
        )
        XCTAssertEqual(job.progress, 0.0)
        job.bytesUploaded = 50
        XCTAssertEqual(job.progress, 0.5)
        job.bytesUploaded = 100
        XCTAssertEqual(job.progress, 1.0)
    }

    func testUploadJobProgressZeroTotal() {
        let job = UploadJob(
            id: 1, filePath: "/tmp/test.txt", r2Key: "test.txt",
            bucket: "b", accountName: "a"
        )
        XCTAssertEqual(job.progress, 0.0)
    }

    func testHistoryEntryEquatable() {
        let entry = HistoryEntry(
            id: 1, fileName: "photo.jpg", fileSize: 1024,
            r2Key: "photos/photo.jpg", bucket: "media",
            accountName: "main", url: "https://example.com/photo.jpg",
            uploadedAt: "2026-02-24T00:00:00Z"
        )
        XCTAssertEqual(entry, entry)
    }

    // MARK: - Config TOML Round-Trip Tests

    func testConfigDefaultValues() {
        let config = R2Config()
        XCTAssertNil(config.activeAccount)
        XCTAssertTrue(config.accounts.isEmpty)
        XCTAssertEqual(config.preferences.concurrentUploads, 4)
        XCTAssertEqual(config.preferences.chunkSizeMb, 8)
        XCTAssertTrue(config.preferences.playSound)
        XCTAssertFalse(config.preferences.launchAtLogin)
        XCTAssertFalse(config.preferences.hideDockIcon)
        XCTAssertTrue(config.preferences.exclusionPatterns.contains(".DS_Store"))
    }

    func testConfigTOMLRoundTrip() throws {
        let original = R2Config(
            activeAccount: "work",
            accounts: [
                ConfigAccount(name: "work", bucket: "my-bucket",
                              path: "uploads/", customDomain: "cdn.example.com"),
                ConfigAccount(name: "personal", bucket: "personal-bucket", path: "")
            ],
            preferences: R2Preferences(
                concurrentUploads: 8, chunkSizeMb: 16,
                exclusionPatterns: [".DS_Store", "*.tmp"],
                launchAtLogin: true, hideDockIcon: true, playSound: false
            )
        )

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let path = tmp.appendingPathComponent("config.toml")
        try ConfigManager.save(original, to: path)
        let loaded = try ConfigManager.load(from: path)

        XCTAssertEqual(loaded.activeAccount, "work")
        XCTAssertEqual(loaded.accounts.count, 2)
        XCTAssertEqual(loaded.accounts[0].name, "work")
        XCTAssertEqual(loaded.accounts[0].bucket, "my-bucket")
        XCTAssertEqual(loaded.accounts[0].path, "uploads/")
        XCTAssertEqual(loaded.accounts[0].customDomain, "cdn.example.com")
        XCTAssertEqual(loaded.accounts[1].name, "personal")
        XCTAssertNil(loaded.accounts[1].customDomain)
        XCTAssertEqual(loaded.preferences.concurrentUploads, 8)
        XCTAssertEqual(loaded.preferences.chunkSizeMb, 16)
        XCTAssertEqual(loaded.preferences.exclusionPatterns, [".DS_Store", "*.tmp"])
        XCTAssertTrue(loaded.preferences.launchAtLogin)
        XCTAssertTrue(loaded.preferences.hideDockIcon)
        XCTAssertFalse(loaded.preferences.playSound)
    }

    func testConfigLoadMissingFileReturnsDefaults() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent/config.toml")
        let config = try ConfigManager.load(from: path)
        XCTAssertEqual(config, R2Config())
    }

    func testConfigParsesRustTOML() {
        // Simulate output from Rust's toml::to_string_pretty()
        let toml = """
        active_account = "test"

        [[accounts]]
        name = "test"
        bucket = "b"
        path = ""

        [preferences]
        concurrent_uploads = 4
        chunk_size_mb = 8
        exclusion_patterns = [
            ".DS_Store",
            "._*",
        ]
        launch_at_login = false
        hide_dock_icon = false
        play_sound = true
        """
        let config = TOMLParser.parse(toml)
        XCTAssertEqual(config.activeAccount, "test")
        XCTAssertEqual(config.accounts.count, 1)
        XCTAssertEqual(config.accounts[0].bucket, "b")
        XCTAssertEqual(config.preferences.exclusionPatterns, [".DS_Store", "._*"])
        XCTAssertTrue(config.preferences.playSound)
    }

    // MARK: - QueueManager Tests

    func testQueueInsertAndGet() throws {
        let queue = try makeQueueManager()
        let id = try queue.insertJob(
            filePath: "/tmp/test.txt", r2Key: "test.txt",
            bucket: "b", accountName: "acct", totalBytes: 1024
        )
        let job = try queue.getJob(id: id)
        XCTAssertNotNil(job)
        XCTAssertEqual(job?.filePath, "/tmp/test.txt")
        XCTAssertEqual(job?.r2Key, "test.txt")
        XCTAssertEqual(job?.status, .pending)
        XCTAssertEqual(job?.totalBytes, 1024)
    }

    func testQueueListByStatus() throws {
        let queue = try makeQueueManager()
        let _ = try queue.insertJob(
            filePath: "/a", r2Key: "a", bucket: "b", accountName: "acct"
        )
        let _ = try queue.insertJob(
            filePath: "/b", r2Key: "b", bucket: "b", accountName: "acct"
        )
        let id3 = try queue.insertJob(
            filePath: "/c", r2Key: "c", bucket: "b", accountName: "acct"
        )
        try queue.updateStatus(id: id3, status: .uploading)

        let pending = try queue.listJobs(status: .pending)
        XCTAssertEqual(pending.count, 2)

        let uploading = try queue.listJobs(status: .uploading)
        XCTAssertEqual(uploading.count, 1)
        XCTAssertEqual(uploading[0].filePath, "/c")
    }

    func testQueueUpdateProgress() throws {
        let queue = try makeQueueManager()
        let id = try queue.insertJob(
            filePath: "/f", r2Key: "k", bucket: "b",
            accountName: "a", totalBytes: 1000
        )
        try queue.updateProgress(id: id, bytesUploaded: 500)
        let job = try queue.getJob(id: id)
        XCTAssertEqual(job?.bytesUploaded, 500)
    }

    func testQueueDelete() throws {
        let queue = try makeQueueManager()
        let id = try queue.insertJob(
            filePath: "/f", r2Key: "k", bucket: "b", accountName: "a"
        )
        XCTAssertTrue(try queue.deleteJob(id: id))
        XCTAssertNil(try queue.getJob(id: id))
        XCTAssertFalse(try queue.deleteJob(id: id))
    }

    // MARK: - HistoryManager Tests

    func testHistoryInsertAndGet() throws {
        let history = try makeHistoryManager()
        let id = try history.insertEntry(
            fileName: "photo.jpg", fileSize: 2048,
            r2Key: "imgs/photo.jpg", bucket: "media",
            accountName: "acct", url: "https://cdn.example.com/photo.jpg"
        )
        let entry = try history.getEntry(id: id)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.fileName, "photo.jpg")
        XCTAssertEqual(entry?.fileSize, 2048)
        XCTAssertEqual(entry?.url, "https://cdn.example.com/photo.jpg")
    }

    func testHistoryListMostRecentFirst() throws {
        let history = try makeHistoryManager()
        try history.insertEntry(
            fileName: "a.txt", fileSize: 100, r2Key: "a", bucket: "b",
            accountName: "a", url: ""
        )
        try history.insertEntry(
            fileName: "b.txt", fileSize: 200, r2Key: "b", bucket: "b",
            accountName: "a", url: ""
        )
        let entries = try history.listEntries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].fileName, "b.txt")
        XCTAssertEqual(entries[1].fileName, "a.txt")
    }

    func testHistorySearch() throws {
        let history = try makeHistoryManager()
        try history.insertEntry(
            fileName: "photo.jpg", fileSize: 100, r2Key: "k", bucket: "b",
            accountName: "a", url: ""
        )
        try history.insertEntry(
            fileName: "document.pdf", fileSize: 200, r2Key: "k", bucket: "b",
            accountName: "a", url: ""
        )
        let results = try history.search(query: "photo")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].fileName, "photo.jpg")

        let empty = try history.search(query: "nonexistent")
        XCTAssertTrue(empty.isEmpty)
    }

    func testHistoryClear() throws {
        let history = try makeHistoryManager()
        try history.insertEntry(
            fileName: "a.txt", fileSize: 100, r2Key: "k", bucket: "b",
            accountName: "a", url: ""
        )
        try history.insertEntry(
            fileName: "b.txt", fileSize: 200, r2Key: "k", bucket: "b",
            accountName: "a", url: ""
        )
        let removed = try history.clear()
        XCTAssertEqual(removed, 2)
        XCTAssertTrue(try history.listEntries().isEmpty)
    }

    // MARK: - AccountManager Tests

    func testAccountManagerAddAndList() throws {
        let mgr = try makeAccountManager()
        try mgr.addAccount(ConfigAccount(name: "work", bucket: "b1", path: "uploads/"))
        XCTAssertEqual(mgr.accounts.count, 1)
        XCTAssertEqual(mgr.activeAccountName, "work")
    }

    func testAccountManagerSwitch() throws {
        let mgr = try makeAccountManager()
        try mgr.addAccount(ConfigAccount(name: "work", bucket: "b1"))
        try mgr.addAccount(ConfigAccount(name: "personal", bucket: "b2"))
        XCTAssertTrue(try mgr.switchAccount(to: "personal"))
        XCTAssertEqual(mgr.activeAccountName, "personal")
        XCTAssertFalse(try mgr.switchAccount(to: "invalid"))
    }

    func testAccountManagerRemove() throws {
        let mgr = try makeAccountManager()
        try mgr.addAccount(ConfigAccount(name: "work", bucket: "b1"))
        try mgr.addAccount(ConfigAccount(name: "personal", bucket: "b2"))
        try mgr.removeAccount(named: "work")
        XCTAssertEqual(mgr.accounts.count, 1)
        XCTAssertEqual(mgr.activeAccountName, "personal")
    }

    func testAccountManagerUpdate() throws {
        let mgr = try makeAccountManager()
        try mgr.addAccount(ConfigAccount(name: "work", bucket: "b1"))
        try mgr.updateAccount(
            ConfigAccount(name: "work", bucket: "b2", path: "new/",
                          customDomain: "cdn.example.com")
        )
        XCTAssertEqual(mgr.account(named: "work")?.bucket, "b2")
        XCTAssertEqual(mgr.account(named: "work")?.customDomain, "cdn.example.com")
    }

    // MARK: - KeychainManager Tests

    func testKeychainSaveAndGet() throws {
        let keychain = makeKeychainManager()
        defer { cleanupKeychain(keychain, accounts: ["test-acct"]) }

        try keychain.saveToken(account: "test-acct", token: "cf-token-abc123")
        let retrieved = try keychain.getToken(account: "test-acct")
        XCTAssertEqual(retrieved, "cf-token-abc123")
    }

    func testKeychainGetNonexistent() throws {
        let keychain = makeKeychainManager()
        let result = try keychain.getToken(account: "no-such-account")
        XCTAssertNil(result)
    }

    func testKeychainSaveDuplicate() throws {
        let keychain = makeKeychainManager()
        defer { cleanupKeychain(keychain, accounts: ["dup-acct"]) }

        try keychain.saveToken(account: "dup-acct", token: "token1")
        XCTAssertThrowsError(try keychain.saveToken(account: "dup-acct", token: "token2")) { error in
            XCTAssertEqual(error as? KeychainError, .duplicateItem)
        }
    }

    func testKeychainUpdate() throws {
        let keychain = makeKeychainManager()
        defer { cleanupKeychain(keychain, accounts: ["upd-acct"]) }

        try keychain.saveToken(account: "upd-acct", token: "old-token")
        try keychain.updateToken(account: "upd-acct", token: "new-token")
        let retrieved = try keychain.getToken(account: "upd-acct")
        XCTAssertEqual(retrieved, "new-token")
    }

    func testKeychainUpdateNonexistent() throws {
        let keychain = makeKeychainManager()
        XCTAssertThrowsError(try keychain.updateToken(account: "ghost", token: "t")) { error in
            XCTAssertEqual(error as? KeychainError, .itemNotFound)
        }
    }

    func testKeychainDelete() throws {
        let keychain = makeKeychainManager()
        // No defer needed — we delete in the test itself.
        try keychain.saveToken(account: "del-acct", token: "doomed-token")
        try keychain.deleteToken(account: "del-acct")
        let result = try keychain.getToken(account: "del-acct")
        XCTAssertNil(result)
    }

    func testKeychainDeleteNonexistent() throws {
        let keychain = makeKeychainManager()
        XCTAssertThrowsError(try keychain.deleteToken(account: "nobody")) { error in
            XCTAssertEqual(error as? KeychainError, .itemNotFound)
        }
    }

    func testKeychainMultipleAccounts() throws {
        let keychain = makeKeychainManager()
        defer { cleanupKeychain(keychain, accounts: ["acct-a", "acct-b"]) }

        try keychain.saveToken(account: "acct-a", token: "token-a")
        try keychain.saveToken(account: "acct-b", token: "token-b")

        XCTAssertEqual(try keychain.getToken(account: "acct-a"), "token-a")
        XCTAssertEqual(try keychain.getToken(account: "acct-b"), "token-b")

        // Deleting one doesn't affect the other.
        try keychain.deleteToken(account: "acct-a")
        XCTAssertNil(try keychain.getToken(account: "acct-a"))
        XCTAssertEqual(try keychain.getToken(account: "acct-b"), "token-b")
    }

    func testKeychainErrorDescription() {
        XCTAssertEqual(
            KeychainError.itemNotFound.localizedDescription,
            "Keychain item not found"
        )
        XCTAssertEqual(
            KeychainError.duplicateItem.localizedDescription,
            "Keychain item already exists"
        )
        XCTAssertTrue(
            KeychainError.unexpectedError(-50).localizedDescription.contains("-50")
        )
    }

    // MARK: - Test Helpers

    /// Unique service per test run to avoid polluting the real Keychain.
    private static let testKeychainService = "com.superhumancorp.r2drop.test.\(UUID().uuidString)"

    private func makeKeychainManager() -> KeychainManager {
        KeychainManager(service: R2CoreTests.testKeychainService, accessGroup: nil)
    }

    /// Best-effort cleanup of test Keychain entries.
    private func cleanupKeychain(_ keychain: KeychainManager, accounts: [String]) {
        for account in accounts {
            try? keychain.deleteToken(account: account)
        }
    }

    private func makeQueueManager() throws -> QueueManager {
        try QueueManager(path: tempDBPath())
    }

    private func makeHistoryManager() throws -> HistoryManager {
        try HistoryManager(path: tempDBPath())
    }

    private func makeAccountManager() throws -> AccountManager {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("config.toml")
        try ConfigManager.save(R2Config(), to: path)
        return try AccountManager(configPath: path)
    }

    private func tempDBPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".db")
            .path
    }
}
