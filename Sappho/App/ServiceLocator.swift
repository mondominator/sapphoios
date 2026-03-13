import Foundation

/// Simple shared container so non-SwiftUI classes (e.g. CarPlaySceneDelegate)
/// can access the shared service instances created by SapphoApp.
final class ServiceLocator {
    static let shared = ServiceLocator()

    var api: SapphoAPI?
    var audioPlayer: AudioPlayerService?
    var authRepository: AuthRepository?

    private init() {}
}
