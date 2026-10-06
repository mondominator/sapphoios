import SwiftUI

/// Shows the player's current problem (stream failed, file ended early) with
/// a Retry button. Playback failures used to be invisible: the UI kept saying
/// "playing" at a frozen position.
struct PlaybackErrorBanner: View {
    @Environment(AudioPlayerService.self) private var audioPlayer

    var body: some View {
        if let message = audioPlayer.playbackError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.sapphoWarning)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.sapphoCaption)
                    .foregroundColor(.sapphoTextHigh)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Retry") {
                    audioPlayer.retryPlayback()
                }
                .font(.sapphoCaption.bold())
                .foregroundColor(.sapphoPrimaryLight)
                .accessibilityHint("Double tap to try playing again")
            }
            .padding(10)
            .background(Color.sapphoSurfaceElevated)
            .cornerRadius(10)
            .accessibilityElement(children: .combine)
        }
    }
}
