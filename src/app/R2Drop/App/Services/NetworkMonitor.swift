// R2Drop/App/Services/NetworkMonitor.swift
// Monitors network connectivity via NWPathMonitor (FR-031).
// Notifies the Rust engine when connectivity changes so the upload
// queue can pause/resume automatically.

import Foundation
import Network
import R2Bridge

/// Observes NWPathMonitor and forwards connectivity changes to the Rust engine.
/// Follows the same start/stop lifecycle pattern as UploadMonitor.
@MainActor
final class NetworkMonitor {

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.superhumancorp.r2drop.network")
    private let client = R2Client()

    /// Whether the network is currently reachable.
    private(set) var isConnected: Bool = true

    // MARK: - Lifecycle

    /// Start observing network path changes.
    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                self?.handleChange(connected: connected)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    /// Stop observing network path changes.
    func stop() {
        monitor.cancel()
    }

    // MARK: - Private

    /// Forward the connectivity change to the Rust engine.
    private func handleChange(connected: Bool) {
        guard connected != isConnected else { return }
        isConnected = connected
        client.setNetworkAvailable(connected)
    }
}
