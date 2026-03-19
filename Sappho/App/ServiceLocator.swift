import Foundation

/// Simple shared container so non-SwiftUI classes (e.g. CarPlaySceneDelegate)
/// can access the shared service instances created by SapphoApp.
///
/// Thread safety: All access is serialized through a serial dispatch queue.
/// Initialization must happen via `configure()` before accessing any properties.
final class ServiceLocator: @unchecked Sendable {
    static let shared = ServiceLocator()

    private let queue = DispatchQueue(label: "com.sappho.servicelocator")
    private var _isConfigured = false
    private var _api: SapphoAPI?
    private var _audioPlayer: AudioPlayerService?
    private var _authRepository: AuthRepository?

    var isConfigured: Bool {
        queue.sync { _isConfigured }
    }

    var api: SapphoAPI? {
        queue.sync {
            assert(_isConfigured, "ServiceLocator.configure() must be called before accessing services")
            return _api
        }
    }

    var audioPlayer: AudioPlayerService? {
        queue.sync {
            assert(_isConfigured, "ServiceLocator.configure() must be called before accessing services")
            return _audioPlayer
        }
    }

    var authRepository: AuthRepository? {
        queue.sync {
            assert(_isConfigured, "ServiceLocator.configure() must be called before accessing services")
            return _authRepository
        }
    }

    func configure(api: SapphoAPI, audioPlayer: AudioPlayerService, authRepository: AuthRepository) {
        queue.sync {
            self._api = api
            self._audioPlayer = audioPlayer
            self._authRepository = authRepository
            self._isConfigured = true
        }
    }

    private init() {}
}
