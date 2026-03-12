import SwiftUI
import AVKit

struct PlayerView: View {
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(\.dismiss) private var dismiss

    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = 30
    @AppStorage("skipBackwardSeconds") private var skipBackwardSeconds = 15

    @State private var showSpeedPicker = false
    @State private var showSleepTimer = false
    @State private var showChapters = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        if let audiobook = audioPlayer.currentAudiobook {
            VStack(spacing: 0) {
                // Drag handle + Header
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.sapphoTextMuted.opacity(0.5))
                        .frame(width: 36, height: 5)
                        .padding(.top, 8)

                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.sapphoTextHigh)
                        }

                        Spacer()

                        // AirPlay (matches Cast button position on Android)
                        AirPlayButton()
                            .frame(width: 28, height: 28)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.height > 0 {
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            if value.translation.height > 100 {
                                dismiss()
                            }
                            dragOffset = 0
                        }
                )

                Spacer()

                VStack(spacing: 28) {
                        // Cover
                        CoverImage(audiobookId: audiobook.id, cornerRadius: 12)
                            .frame(width: 280, height: 280)
                            .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)

                        // Title and Author
                        VStack(spacing: 6) {
                            Text(audiobook.title)
                                .font(.sapphoHeadline)
                                .foregroundColor(.sapphoTextHigh)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)

                            Text(audiobook.author ?? "Unknown Author")
                                .font(.sapphoBody)
                                .foregroundColor(.sapphoTextMuted)

                            // Series info
                            if let series = audiobook.series {
                                HStack(spacing: 4) {
                                    Text(series)
                                    if let pos = audiobook.seriesPosition {
                                        Text("#\(formatSeriesPosition(pos))")
                                    }
                                }
                                .font(.sapphoCaption)
                                .foregroundColor(.sapphoTextMuted.opacity(0.8))
                            }

                            // Current chapter
                            if let chapter = audioPlayer.currentChapter {
                                Text(chapter.title ?? "Chapter \(chapter.id)")
                                    .font(.sapphoCaption)
                                    .foregroundColor(.sapphoPrimary)
                                    .padding(.top, 2)
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
                            .tint(Color(red: 0.376, green: 0.647, blue: 0.980))

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
                        HStack(spacing: 0) {
                            Spacer()

                            // Previous chapter
                            Button {
                                jumpToPreviousChapter()
                            } label: {
                                Image(systemName: "backward.end.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(hasChapters ? .sapphoTextHigh : Color(red: 0.294, green: 0.333, blue: 0.388))
                            }
                            .disabled(!hasChapters)
                            .frame(width: 48, height: 48)

                            Spacer()

                            // Skip backward (Replay 10)
                            Button {
                                audioPlayer.skipBackward(seconds: 10)
                            } label: {
                                Image(systemName: "gobackward.10")
                                    .font(.system(size: 32))
                                    .foregroundColor(.sapphoTextHigh)
                            }
                            .frame(width: 52)

                            Spacer()

                            // Play/Pause (always blue on full player)
                            Button {
                                audioPlayer.togglePlayPause()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(red: 0.376, green: 0.647, blue: 0.980)) // #60A5FA
                                        .frame(width: 72, height: 72)
                                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 28))
                                        .foregroundColor(.white)
                                }
                            }

                            Spacer()

                            // Skip forward (Forward 10)
                            Button {
                                audioPlayer.skipForward(seconds: 10)
                            } label: {
                                Image(systemName: "goforward.10")
                                    .font(.system(size: 32))
                                    .foregroundColor(.sapphoTextHigh)
                            }
                            .frame(width: 52)

                            Spacer()

                            // Next chapter
                            Button {
                                jumpToNextChapter()
                            } label: {
                                Image(systemName: "forward.end.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(hasChapters ? .sapphoTextHigh : Color(red: 0.294, green: 0.333, blue: 0.388))
                            }
                            .disabled(!hasChapters)
                            .frame(width: 48, height: 48)

                            Spacer()
                        }

                        // Secondary Controls (matches Android: Chapters | Speed | Sleep)
                        HStack(spacing: 0) {
                            // Chapters
                            if let chapters = audiobook.chapters, !chapters.isEmpty {
                                Button {
                                    showChapters = true
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: "list.bullet")
                                            .font(.system(size: 20))
                                            .foregroundColor(.sapphoPrimary)
                                        Text(audioPlayer.currentChapter?.title ?? "Chapters")
                                            .font(.sapphoSmall)
                                            .foregroundColor(.sapphoTextHigh)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                }
                            }

                            // Speed
                            Button {
                                showSpeedPicker = true
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "speedometer")
                                        .font(.system(size: 20))
                                        .foregroundColor(.purple)
                                    Text(String(format: "%.2gx", audioPlayer.playbackSpeed))
                                        .font(.sapphoSmall)
                                        .foregroundColor(.sapphoTextHigh)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }

                            // Sleep Timer
                            Button {
                                showSleepTimer = true
                            } label: {
                                VStack(spacing: 6) {
                                    if let remaining = audioPlayer.sleepTimerRemaining {
                                        Image(systemName: "moon.zzz.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(.sapphoWarning)
                                        Text(formatTime(remaining))
                                            .font(.sapphoSmall)
                                            .foregroundColor(.sapphoWarning)
                                    } else {
                                        Image(systemName: "moon.zzz")
                                            .font(.system(size: 20))
                                            .foregroundColor(.sapphoWarning)
                                        Text("Off")
                                            .font(.sapphoSmall)
                                            .foregroundColor(.sapphoTextHigh)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                        }
                        .padding(.top, 8)

                        // Playing animation bars
                        PlayingAnimationBars()
                            .padding(.top, 8)
                            .opacity(audioPlayer.isPlaying ? 1 : 0)
                    }
                    .padding(.vertical, 16)

                Spacer()
            }
            .offset(y: dragOffset)
            .animation(.interactiveSpring(), value: dragOffset)
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
                ChaptersSheet(
                    chapters: audiobook.chapters ?? [],
                    currentChapter: audioPlayer.currentChapter
                ) { chapter in
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

    // MARK: - Chapter Navigation

    private var hasChapters: Bool {
        guard let chapters = audioPlayer.currentAudiobook?.chapters else { return false }
        return !chapters.isEmpty
    }

    private func jumpToPreviousChapter() {
        guard let chapters = audioPlayer.currentAudiobook?.chapters,
              let current = audioPlayer.currentChapter,
              let currentIndex = chapters.firstIndex(where: { $0.id == current.id }),
              currentIndex > 0 else { return }
        audioPlayer.jumpToChapter(chapters[currentIndex - 1])
    }

    private func jumpToNextChapter() {
        guard let chapters = audioPlayer.currentAudiobook?.chapters,
              let current = audioPlayer.currentChapter,
              let currentIndex = chapters.firstIndex(where: { $0.id == current.id }),
              currentIndex < chapters.count - 1 else { return }
        audioPlayer.jumpToChapter(chapters[currentIndex + 1])
    }

    // MARK: - Formatting

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

    private func formatSeriesPosition(_ position: Float) -> String {
        if position == floor(position) {
            return String(format: "%.0f", position)
        }
        return String(format: "%.1f", position)
    }

    private var skipBackwardIcon: String {
        let validSeconds = [5, 10, 15, 30, 45, 60, 75, 90]
        let seconds = validSeconds.contains(skipBackwardSeconds) ? skipBackwardSeconds : 15
        return "gobackward.\(seconds)"
    }

    private var skipForwardIcon: String {
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

    private let options = [5, 10, 15, 30, 45, 60, 90, 120]

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

// MARK: - Playing Animation Bars
struct PlayingAnimationBars: View {
    @State private var animating = false

    private let targetHeights: [CGFloat] = [12, 7, 10]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 0.376, green: 0.647, blue: 0.980)) // #60A5FA
                    .frame(width: 3, height: animating ? targetHeights[index] : 3)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                        value: animating
                    )
            }
        }
        .frame(height: 12)
        .onAppear { animating = true }
    }
}

#Preview {
    PlayerView()
        .environment(AuthRepository())
        .environment(AudioPlayerService())
}
