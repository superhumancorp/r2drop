import Foundation
import UniformTypeIdentifiers
import R2Core

/// macOS Quick Action (Action extension) entry point.
/// Receives selected Finder items, writes upload jobs to the shared App Group queue,
/// then wakes the main app so its FinderQueueBridge transfers them immediately.
final class QuickActionRequestHandler: NSObject, NSExtensionRequestHandling {

    private enum QuickActionError: Int {
        case noInput = 1
        case noFiles = 2
        case queueOpenFailed = 3
        case noActiveAccount = 4
    }

    func beginRequest(with context: NSExtensionContext) {
        extractFileURLs(from: context.inputItems) { [weak self] urls in
            guard let self else { return }
            self.handle(urls: urls, context: context)
        }
    }

    // MARK: - Main flow

    private func handle(urls: [URL], context: NSExtensionContext) {
        let normalizedURLs = deduplicatedFileURLs(urls)
        guard !normalizedURLs.isEmpty else {
            cancel(
                context,
                code: .noFiles,
                message: "No files or folders were provided to R2Drop."
            )
            return
        }

        let config: R2Config
        do {
            config = try ConfigManager.load()
        } catch {
            NSLog("R2Drop QuickAction: failed to load config: %@", String(describing: error))
            // Best effort: open the app so the user can recover.
            openApp(urlString: "\(R2CoreConstants.urlScheme)://status", in: context)
            cancel(context, code: .noInput, message: "R2Drop could not load its configuration.")
            return
        }

        guard let activeName = config.activeAccount,
              let account = config.accounts.first(where: { $0.name == activeName }) else {
            NSLog("R2Drop QuickAction: no active account configured")
            openApp(urlString: "\(R2CoreConstants.urlScheme)://auth/setup", in: context)
            complete(context)
            return
        }

        guard let qm = try? QueueManager(appGroup: R2CoreConstants.appGroup) else {
            cancel(context, code: .queueOpenFailed, message: "Could not open the shared R2Drop upload queue.")
            return
        }

        let exclusions = config.preferences.exclusionPatterns
        var insertedCount = 0

        for url in normalizedURLs {
            let fileName = url.lastPathComponent
            guard !matchesExclusionPattern(fileName, patterns: exclusions) else { continue }

            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            insertedCount += queueURL(url, account: account, qm: qm, exclusions: exclusions)
        }

        NSLog("R2Drop QuickAction: queued %ld job(s) from %ld selected item(s)",
              insertedCount, normalizedURLs.count)

        if insertedCount > 0 {
            openApp(urlString: "\(R2CoreConstants.urlScheme)://status", in: context)
            complete(context)
        } else {
            cancel(
                context,
                code: .noFiles,
                message: "No uploadable files were found (items may be excluded or inaccessible)."
            )
        }
    }

    // MARK: - Input extraction

    private func extractFileURLs(from inputItems: [Any], completion: @escaping ([URL]) -> Void) {
        let extensionItems = inputItems.compactMap { $0 as? NSExtensionItem }
        let providers = extensionItems.flatMap { $0.attachments ?? [] }

        guard !providers.isEmpty else {
            completion([])
            return
        }

        let preferredTypes = [
            UTType.fileURL.identifier,
            UTType.url.identifier,
            "public.file-url",
            "public.url"
        ]

        let group = DispatchGroup()
        let lock = NSLock()
        var collected: [URL] = []

        for provider in providers {
            guard let type = preferredTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else {
                continue
            }

            group.enter()
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                defer { group.leave() }

                if let error {
                    NSLog("R2Drop QuickAction: provider load error: %@", String(describing: error))
                    return
                }

                let urls = Self.urls(fromItemProviderPayload: item)
                guard !urls.isEmpty else { return }
                lock.lock()
                collected.append(contentsOf: urls)
                lock.unlock()
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            completion(collected)
        }
    }

    private static func urls(fromItemProviderPayload item: NSSecureCoding?) -> [URL] {
        if let url = item as? URL {
            return [url]
        }
        if let nsurl = item as? NSURL, let url = nsurl as URL? {
            return [url]
        }
        if let string = item as? String, let url = URL(string: string) {
            return [url]
        }
        if let array = item as? [Any] {
            return array.compactMap { element in
                if let url = element as? URL { return url }
                if let nsurl = element as? NSURL { return nsurl as URL }
                if let string = element as? String { return URL(string: string) }
                return nil
            }
        }
        if let data = item as? Data {
            let nsurl = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil)
            return [nsurl as URL]
        }
        return []
    }

    private func deduplicatedFileURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls where url.isFileURL {
            let standardized = url.standardizedFileURL
            let key = standardized.path
            if seen.insert(key).inserted {
                result.append(standardized)
            }
        }
        return result
    }

    // MARK: - Queueing

    @discardableResult
    private func queueURL(
        _ url: URL,
        account: ConfigAccount,
        qm: QueueManager,
        exclusions: [String]
    ) -> Int {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

        if isDirectory {
            return queueDirectory(url, account: account, qm: qm, exclusions: exclusions)
        }

        let name = url.lastPathComponent
        let pathPrefix = account.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let r2Key = pathPrefix.isEmpty ? name : "\(pathPrefix)/\(name)"
        let size = fileSize(url)

        do {
            _ = try qm.insertJob(
                filePath: url.path,
                r2Key: r2Key,
                bucket: account.bucket,
                accountName: account.name,
                totalBytes: size
            )
            return 1
        } catch {
            NSLog("R2Drop QuickAction: failed to queue file %@: %@", url.path, String(describing: error))
            return 0
        }
    }

    private func queueDirectory(
        _ rootURL: URL,
        account: ConfigAccount,
        qm: QueueManager,
        exclusions: [String]
    ) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        let baseName = rootURL.lastPathComponent
        let pathPrefix = account.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var inserted = 0

        while let fileURL = enumerator.nextObject() as? URL {
            let isFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            guard isFile else { continue }

            let fileName = fileURL.lastPathComponent
            guard !matchesExclusionPattern(fileName, patterns: exclusions) else { continue }

            let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            let keyName = "\(baseName)/\(relativePath)"
            let r2Key = pathPrefix.isEmpty ? keyName : "\(pathPrefix)/\(keyName)"
            let size = fileSize(fileURL)

            do {
                _ = try qm.insertJob(
                    filePath: fileURL.path,
                    r2Key: r2Key,
                    bucket: account.bucket,
                    accountName: account.name,
                    totalBytes: size
                )
                inserted += 1
            } catch {
                NSLog("R2Drop QuickAction: failed to queue file %@: %@", fileURL.path, String(describing: error))
            }
        }
        return inserted
    }

    // MARK: - Helpers

    private func fileSize(_ url: URL) -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? UInt64 ?? 0
    }

    private func matchesExclusionPattern(_ filename: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if pattern.contains("*") {
                if pattern.hasPrefix("*") {
                    let suffix = String(pattern.dropFirst())
                    if filename.hasSuffix(suffix) { return true }
                } else if pattern.hasSuffix("*") {
                    let prefix = String(pattern.dropLast())
                    if filename.hasPrefix(prefix) { return true }
                } else {
                    let parts = pattern.split(separator: "*", maxSplits: 1)
                    if parts.count == 2,
                       filename.hasPrefix(String(parts[0])),
                       filename.hasSuffix(String(parts[1])) {
                        return true
                    }
                }
            } else if filename == pattern {
                return true
            }
        }
        return false
    }

    private func openApp(urlString: String, in context: NSExtensionContext) {
        guard let url = URL(string: urlString) else { return }
        context.open(url) { success in
            if !success {
                NSLog("R2Drop QuickAction: failed to open host app via %@", urlString)
            }
        }
    }

    private func complete(_ context: NSExtensionContext) {
        context.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func cancel(_ context: NSExtensionContext, code: QuickActionError, message: String) {
        let error = NSError(
            domain: "com.superhumancorp.r2drop.quickaction",
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
        context.cancelRequest(withError: error)
    }
}
