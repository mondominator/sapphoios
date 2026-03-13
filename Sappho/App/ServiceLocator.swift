import Foundation

/// Simple shared container so non-SwiftUI classes (e.g. CarPlaySceneDelegate)
/// can access the shared service instances created by SapphoApp.
final class ServiceLocator {
    static let shared = ServiceLocator()

    private(set) var api: SapphoAPI?
    private(set) var audioPlayer: AudioPlayerService?
    private(set) var authRepository: AuthRepository?

    func configure(api: SapphoAPI, audioPlayer: AudioPlayerService, authRepository: AuthRepository) {
        self.api = api
        self.audioPlayer = audioPlayer
        self.authRepository = authRepository
    }

    private init() {}
}
