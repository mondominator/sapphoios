import SwiftUI
import AVKit

struct PlayerView: View {
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Binding var showFullPlayer: Bool

    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = 30
    @AppStorage("skipBackwardSeconds") private var skipBackwardSeconds = 15

    @State private var showSpeedPicker = false
    @State private var showSleepTimer = false
    @State private var showChapters = false
    @State private var dragOffset: CGFloat = 0
    @State private var isPulsing = false

    var body: some View {
        if let audiobook = audioPlayer.currentAudiobook {
            ZStack {
                Color.sapphoBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Drag handle + Header
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.sapphoTextMuted.opacity(0.5))
                        .frame(width: 36, height: 5)
                        .padding(.top, 8)

                    HStack {
                        Button {
                            showFullPlayer = false
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

                            // Play/Pause
                            Button {
                                audioPlayer.togglePlayPause()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(audioPlayer.isPlaying
                                            ? Color(red: 0.204, green: 0.827, blue: 0.600)  // #34D399 green
                                            : Color(red: 0.376, green: 0.647, blue: 0.980)) // #60A5FA blue
                                        .frame(width: 72, height: 72)
                                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 28))
                                        .foregroundColor(.white)
                                }
                                .scaleEffect(audioPlayer.isPlaying && isPulsing ? 1.08 : 1.0)
                                .opacity(audioPlayer.isPlaying && isPulsing ? 0.85 : 1.0)
                            }
                            .onChange(of: audioPlayer.isPlaying) { _, playing in
                                if playing {
                                    withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                                        isPulsing = true
                                    }
                                } else {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        isPulsing = false
                                    }
                                }
                            }
                            .onAppear {
                                if audioPlayer.isPlaying {
                                    withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                                        isPulsing = true
                                    }
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
                            // Chapters (always visible, disabled if no chapters)
                            Button {
                                showChapters = true
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "list.bullet")
                                        .font(.system(size: 20))
                                        .foregroundColor(hasChapters ? .sapphoPrimary : Color(red: 0.294, green: 0.333, blue: 0.388))
                                    Text(audioPlayer.currentChapter?.title ?? "Chapters")
                                        .font(.sapphoSmall)
                                        .foregroundColor(hasChapters ? .sapphoTextHigh : Color(red: 0.294, green: 0.333, blue: 0.388))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .disabled(!hasChapters)

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
            .contentShape(Rectangle())
            .offset(y: dragOffset)
            .animation(.interactiveSpring(), value: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 120 {
                            showFullPlayer = false
                        }
                        dragOffset = 0
                    }
            )
            } // end ZStack
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

    @State private var speed: Float

    init(currentSpeed: Float, onSelect: @escaping (Float) -> Void) {
        self.currentSpeed = currentSpeed
        self.onSelect = onSelect
        self._speed = State(initialValue: currentSpeed)
    }

    private let presets: [Float] = [0.75, 1.0, 1.25, 1.3, 1.5, 2.0]

    private var displaySpeed: String {
        if speed == Float(Int(speed)) {
            return String(format: "%.0fx", speed)
        } else {
            return String(format: "%.2gx", speed)
        }
    }

    private func formatPreset(_ value: Float) -> String {
        if value == Float(Int(value)) {
            return String(format: "%.0fx", value)
        } else {
            return String(format: "%.2gx", value)
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            // Handle
            Capsule()
                .fill(Color.sapphoTextMuted.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            Text("Playback Speed")
                .font(.sapphoHeadline)
                .foregroundColor(.sapphoTextHigh)

            // Current speed display with fine-tune controls
            HStack(spacing: 24) {
                Button {
                    adjustSpeed(by: -0.05)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.sapphoPrimary)
                }

                Text(displaySpeed)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.sapphoTextHigh)
                    .frame(minWidth: 100)
                    .contentTransition(.numericText())

                Button {
                    adjustSpeed(by: 0.05)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.sapphoPrimary)
                }
            }

            // Preset buttons
            HStack(spacing: 10) {
                ForEach(presets, id: \.self) { preset in
                    Button {
                        speed = preset
                        onSelect(preset)
                    } label: {
                        Text(formatPreset(preset))
                            .font(.sapphoCaption)
                            .fontWeight(speed == preset ? .semibold : .regular)
                            .foregroundColor(speed == preset ? .white : .sapphoTextHigh)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(speed == preset ? Color.sapphoPrimary : Color.sapphoSurface)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .background(Color.sapphoBackground)
    }

    private func adjustSpeed(by delta: Float) {
        let newSpeed = max(0.5, min(3.0, speed + delta))
        speed = (newSpeed * 20).rounded() / 20
        onSelect(speed)
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
        VStack(spacing: 24) {
            // Handle
            Capsule()
                .fill(Color.sapphoTextMuted.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            Text("Sleep Timer")
                .font(.sapphoHeadline)
                .foregroundColor(.sapphoTextHigh)

            if let remaining = currentRemaining {
                // Active timer display
                VStack(spacing: 8) {
                    Text(formatTime(remaining))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.sapphoWarning)
                    Text("remaining")
                        .font(.sapphoCaption)
                        .foregroundColor(.sapphoTextMuted)
                }

                Button {
                    onCancel()
                    dismiss()
                } label: {
                    Text("Cancel Timer")
                        .font(.sapphoSubheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.sapphoSurface)
                        .cornerRadius(8)
                }
                .padding(.horizontal, 16)
            }

            // Timer options
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 10) {
                ForEach(options, id: \.self) { minutes in
                    Button {
                        onSet(minutes)
                        dismiss()
                    } label: {
                        Text("\(minutes) min")
                            .font(.sapphoCaption)
                            .fontWeight(.medium)
                            .foregroundColor(.sapphoTextHigh)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color.sapphoSurface)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .background(Color.sapphoBackground)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
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
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            AnimatingBar(targetHeight: 12, delay: 0)
            AnimatingBar(targetHeight: 7, delay: 0.1)
            AnimatingBar(targetHeight: 10, delay: 0.2)
        }
        .frame(height: 12)
    }
}

private struct AnimatingBar: View {
    let targetHeight: CGFloat
    let delay: Double
    @State private var animating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(red: 0.376, green: 0.647, blue: 0.980))
            .frame(width: 3, height: animating ? targetHeight : 3)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(delay)) {
                    animating = true
                }
            }
    }
}

#Preview {
    PlayerView(showFullPlayer: .constant(true))
        .environment(AuthRepository())
        .environment(AudioPlayerService())
}
