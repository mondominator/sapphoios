import SwiftUI

struct PlayerView: View {
    @Environment(\.sapphoAPI) private var api
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(\.dismiss) private var dismiss

    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = 30
    @AppStorage("skipBackwardSeconds") private var skipBackwardSeconds = 15

    @State private var showSpeedPicker = false
    @State private var showSleepTimer = false
    @State private var showChapters = false

    var body: some View {
        if let audiobook = audioPlayer.currentAudiobook {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.sapphoTextHigh)
                    }

                    Spacer()

                    // Chapter button
                    if audiobook.chapters != nil {
                        Button {
                            showChapters = true
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 18))
                                .foregroundColor(.sapphoTextHigh)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                ScrollView {
                    VStack(spacing: 32) {
                        // Cover
                        AsyncImage(url: api?.coverURL(for: audiobook.id)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Rectangle()
                                .fill(Color.sapphoSurface)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(
                                    Image(systemName: "book.closed.fill")
                                        .font(.system(size: 64))
                                        .foregroundColor(.sapphoTextMuted)
                                )
                        }
                        .frame(maxWidth: 300, maxHeight: 300)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)

                        // Title and Author
                        VStack(spacing: 8) {
                            Text(audiobook.title)
                                .font(.sapphoHeadline)
                                .foregroundColor(.sapphoTextHigh)
                                .multilineTextAlignment(.center)

                            Text(audiobook.author ?? "Unknown Author")
                                .font(.sapphoBody)
                                .foregroundColor(.sapphoTextMuted)

                            // Current chapter
                            if let chapter = audioPlayer.currentChapter {
                                Text(chapter.title ?? "Chapter \(chapter.id)")
                                    .font(.sapphoCaption)
                                    .foregroundColor(.sapphoPrimary)
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Progress Slider
                        VStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { audioPlayer.position },
                                    set: { newValue in
                                        Task {
                                            await audioPlayer.seek(to: newValue)
                                        }
                                    }
                                ),
                                in: 0...max(audioPlayer.duration, 1)
                            )
                            .tint(.sapphoPrimary)

                            HStack {
                                Text(formatTime(audioPlayer.position))
                                Spacer()
                                Text("-" + formatTime(audioPlayer.duration - audioPlayer.position))
                            }
                            .font(.sapphoSmall)
                            .foregroundColor(.sapphoTextMuted)
                        }
                        .padding(.horizontal, 20)

                        // Playback Controls
                        HStack(spacing: 40) {
                            // Skip backward
                            Button {
                                audioPlayer.skipBackward(seconds: TimeInterval(skipBackwardSeconds))
                            } label: {
                                Image(systemName: skipBackwardIcon)
                                    .font(.system(size: 32))
                                    .foregroundColor(.sapphoTextHigh)
                            }

                            // Play/Pause
                            Button {
                                audioPlayer.togglePlayPause()
                            } label: {
                                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 72))
                                    .foregroundColor(.sapphoPrimary)
                            }

                            // Skip forward
                            Button {
                                audioPlayer.skipForward(seconds: TimeInterval(skipForwardSeconds))
                            } label: {
                                Image(systemName: skipForwardIcon)
                                    .font(.system(size: 32))
                                    .foregroundColor(.sapphoTextHigh)
                            }
                        }

                        // Secondary Controls
                        HStack(spacing: 48) {
                            // Speed
                            Button {
                                showSpeedPicker = true
                            } label: {
                                VStack(spacing: 4) {
                                    Text(String(format: "%.1fx", audioPlayer.playbackSpeed))
                                        .font(.sapphoSubheadline)
                                        .foregroundColor(.sapphoTextHigh)
                                    Text("Speed")
                                        .font(.sapphoSmall)
                                        .foregroundColor(.sapphoTextMuted)
                                }
                            }

                            // Sleep Timer
                            Button {
                                showSleepTimer = true
                            } label: {
                                VStack(spacing: 4) {
                                    if let remaining = audioPlayer.sleepTimerRemaining {
                                        Text(formatTime(remaining))
                                            .font(.sapphoSubheadline)
                                            .foregroundColor(.sapphoPrimary)
                                    } else {
                                        Image(systemName: "moon.zzz")
                                            .font(.system(size: 18))
                                            .foregroundColor(.sapphoTextHigh)
                                    }
                                    Text("Sleep")
                                        .font(.sapphoSmall)
                                        .foregroundColor(.sapphoTextMuted)
                                }
                            }

                            // AirPlay
                            AirPlayButton()
                                .frame(width: 44, height: 44)
                        }
                        .padding(.top, 16)
                    }
                    .padding(.vertical, 20)
                }
            }
            .background(Color.sapphoBackground)
            .sheet(isPresented: $showSpeedPicker) {
                SpeedPickerSheet(currentSpeed: audioPlayer.playbackSpeed) { speed in
                    audioPlayer.setPlaybackSpeed(speed)
                }
                .presentationDetents([.height(300)])
            }
            .sheet(isPresented: $showSleepTimer) {
                SleepTimerSheet(
                    currentRemaining: audioPlayer.sleepTimerRemaining,
                    onSet: { minutes in
                        audioPlayer.setSleepTimer(minutes: minutes)
                    },
                    onCancel: {
                        audioPlayer.cancelSleepTimer()
                    }
                )
                .presentationDetents([.height(350)])
            }
            .sheet(isPresented: $showChapters) {
                ChaptersSheet(chapters: audiobook.chapters ?? [], currentChapter: audioPlayer.currentChapter) { chapter in
                    audioPlayer.jumpToChapter(chapter)
                    showChapters = false
                }
            }
        } else {
            EmptyStateView(
                icon: "waveform",
                title: "Nothing Playing",
                message: "Select an audiobook to start listening"
            )
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private var skipBackwardIcon: String {
        // SF Symbols supports: gobackward.5, .10, .15, .30, .45, .60, .75, .90
        let validSeconds = [5, 10, 15, 30, 45, 60, 75, 90]
        let seconds = validSeconds.contains(skipBackwardSeconds) ? skipBackwardSeconds : 15
        return "gobackward.\(seconds)"
    }

    private var skipForwardIcon: String {
        // SF Symbols supports: goforward.5, .10, .15, .30, .45, .60, .75, .90
        let validSeconds = [5, 10, 15, 30, 45, 60, 75, 90]
        let seconds = validSeconds.contains(skipForwardSeconds) ? skipForwardSeconds : 30
        return "goforward.\(seconds)"
    }
}

// MARK: - AirPlay Button
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let routePickerView = AVRoutePickerView()
        routePickerView.tintColor = UIColor(Color.sapphoTextHigh)
        routePickerView.activeTintColor = UIColor(Color.sapphoPrimary)
        return routePickerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

import AVKit

// MARK: - Speed Picker Sheet
struct SpeedPickerSheet: View {
    let currentSpeed: Float
    let onSelect: (Float) -> Void

    @Environment(\.dismiss) private var dismiss

    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        VStack(spacing: 16) {
            Text("Playback Speed")
                .font(.sapphoHeadline)
                .foregroundColor(.sapphoTextHigh)
                .padding(.top, 20)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 12) {
                ForEach(speeds, id: \.self) { speed in
                    Button {
                        onSelect(speed)
                        dismiss()
                    } label: {
                        Text(String(format: "%.2gx", speed))
                            .font(.sapphoSubheadline)
                            .foregroundColor(speed == currentSpeed ? .white : .sapphoTextHigh)
                            .frame(width: 60, height: 44)
                            .background(speed == currentSpeed ? Color.sapphoPrimary : Color.sapphoSurface)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color.sapphoBackground)
    }
}

// MARK: - Sleep Timer Sheet
struct SleepTimerSheet: View {
    let currentRemaining: TimeInterval?
    let onSet: (Int) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let options = [5, 10, 15, 30, 45, 60]

    var body: some View {
        VStack(spacing: 16) {
            Text("Sleep Timer")
                .font(.sapphoHeadline)
                .foregroundColor(.sapphoTextHigh)
                .padding(.top, 20)

            if currentRemaining != nil {
                Button {
                    onCancel()
                    dismiss()
                } label: {
                    Text("Cancel Timer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SapphoSecondaryButtonStyle())
                .padding(.horizontal, 20)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
                ForEach(options, id: \.self) { minutes in
                    Button {
                        onSet(minutes)
                        dismiss()
                    } label: {
                        Text("\(minutes) min")
                            .font(.sapphoSubheadline)
                            .foregroundColor(.sapphoTextHigh)
                            .frame(width: 80, height: 44)
                            .background(Color.sapphoSurface)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color.sapphoBackground)
    }
}

// MARK: - Chapters Sheet
struct ChaptersSheet: View {
    let chapters: [Chapter]
    let currentChapter: Chapter?
    let onSelect: (Chapter) -> Void

    var body: some View {
        NavigationStack {
            List(chapters) { chapter in
                Button {
                    onSelect(chapter)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(chapter.title ?? "Chapter \(chapter.id)")
                                .font(.sapphoBody)
                                .foregroundColor(chapter.id == currentChapter?.id ? .sapphoPrimary : .sapphoTextHigh)

                            if let duration = chapter.duration {
                                Text(formatDuration(Int(duration)))
                                    .font(.sapphoSmall)
                                    .foregroundColor(.sapphoTextMuted)
                            }
                        }

                        Spacer()

                        if chapter.id == currentChapter?.id {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundColor(.sapphoPrimary)
                        }
                    }
                }
                .listRowBackground(Color.sapphoSurface)
            }
            .listStyle(.plain)
            .background(Color.sapphoBackground)
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes) min"
    }
}

#Preview {
    PlayerView()
        .environment(AuthRepository())
        .environment(AudioPlayerService())
}
