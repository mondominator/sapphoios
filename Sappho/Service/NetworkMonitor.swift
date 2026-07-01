import Foundation
import Network

/// Observes network reachability so views can react to going offline/online.
///
/// Monitoring starts as soon as `shared` is first accessed — that happens at
/// app launch (see `SapphoApp.init`), so by the time the Home screen loads the
/// connection state already reflects reality and we can skip requests that
/// would otherwise sit on a socket timeout while the user stares at a spinner.
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// True when the device has a usable network path. Starts optimistically
    /// `true` and is corrected by the first path update, which the system
    /// delivers within moments of `start(queue:)`.
    private(set) var isConnected: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.sappho.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                self?.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }
}
