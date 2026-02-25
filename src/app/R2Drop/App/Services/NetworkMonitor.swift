// R2Drop/App/Services/NetworkMonitor.swift
// Monitors network connectivity via NWPathMonitor (FR-031).
// Notifies the Rust engine when connectivity changes so the upload
// queue can pause/resume automatically.
// Includes debounce to avoid false disconnects from NWPathMonitor flickering.

import Foundation
import Network
import R2Bridge

/// Observes NWPathMonitor and forwards connectivity changes to the Rust engine.
/// Follows the same start/stop lifecycle pattern as UploadMonitor.
/// Debounces "disconnected" transitions by 2 seconds to avoid false positives
/// that can occur when NWPathMonitor briefly flickers on startup or network change.
@MainActor
final class NetworkMonitor {

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.superhumancorp.r2drop.network")
    private let client = R2Client()

    /// Whether the network is currently reachable.
    private(set) var isConnected: Bool = true

    /// Debounce timer for disconnect events — prevents false disconnects.
    private var disconnectDebounce: DispatchWorkItem?

    /// How long to wait before acting on a disconnect signal.
    private let debounceInterval: TimeInterval = 2.0

    // MARK: - Lifecycle

    /// Start observing network path changes.
    func start() {
        #if DEBUG
        R2Log.network.debug("NetworkMonitor: start")
        #endif
        // Assume connected on start — NWPathMonitor's first callback
        // can briefly report .unsatisfied before settling.
        isConnected = true
        client.setNetworkAvailable(true)

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
        #if DEBUG
        R2Log.network.debug("NetworkMonitor: stop")
        #endif
        disconnectDebounce?.cancel()
        disconnectDebounce = nil
        monitor.cancel()
    }

    // MARK: - Private

    /// Forward the connectivity change to the Rust engine with debounce on disconnect.
    private func handleChange(connected: Bool) {
        if connected {
            // Reconnect immediately — cancel any pending disconnect
            disconnectDebounce?.cancel()
            disconnectDebounce = nil

            guard !isConnected else { return }
            #if DEBUG
            R2Log.network.debug("NetworkMonitor: reconnected")
            #endif
            isConnected = true
            client.setNetworkAvailable(true)
        } else {
            // Debounce disconnect — NWPathMonitor can briefly flicker
            guard isConnected else { return }
            #if DEBUG
            R2Log.network.debug("NetworkMonitor: disconnect signal received, debouncing \(self.debounceInterval)s")
            #endif

            disconnectDebounce?.cancel()
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self = self, self.isConnected else { return }
                    #if DEBUG
                    R2Log.network.debug("NetworkMonitor: confirmed disconnected after debounce")
                    #endif
                    self.isConnected = false
                    self.client.setNetworkAvailable(false)
                }
            }
            disconnectDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
        }
    }
}
