import SwiftUI
import AVKit

struct PlayerView: View {
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Binding var showFullPlayer: Bool

    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = 30
    @AppStorage("skipBackwardSeconds") private var skipBackwardSeconds = 15

    @AppStorage("showChapterProgress") private var showChapterProgress = false

    @State private var showSpeedPicker = false
    @State private var showSleepTimer = false
    @State private var showChapters = false
    @State private var dragOffset: CGFloat = 0
    @State private var isPulsing = false
    @State private var isSeeking = false
    @State private var seekPosition: TimeInterval = 0

    var body: some View {
        if let audiobook = audioPlayer.currentAudiobook {
            ZStack {
                Color.sapphoBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Drag handle + Header (outside drag gesture)
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
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Minimize player")
                        .accessibilityHint("Double tap to minimize to mini player")

                        Spacer()

                        if audioPlayer.isPlaying {
                            PlayingAnimationBars()
                                .accessibilityHidden(true)
                        }

                        Spacer()

                        // AirPlay (matches Cast button position on Android)
                        AirPlayButton()
                            .frame(width: 44, height: 44)
                            .accessibilityLabel("AirPlay")
                            .accessibilityHint("Double tap to choose audio output device")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
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
                            if showChapterProgress, let chapter = audioPlayer.currentChapter {
                                // Chapter-scoped slider
                                let chapterStart = chapter.startTime
                                let chapterDuration = max(chapter.duration ?? (audioPlayer.duration - chapterStart), 1)
                                let chapterPosition = audioPlayer.position - chapterStart

                                Slider(
                                    value: Binding(
                                        get: { isSeeking ? seekPosition : max(0, chapterPosition) },
                                        set: { newValue in
                                            isSeeking = true
                                            seekPosition = newValue
                                        }
                                    ),
                                    in: 0...chapterDuration
                                ) { editing in
                                    if !editing {
                                        Task {
                                            await audioPlayer.seek(to: chapterStart + seekPosition)
                                        }
                                        isSeeking = false
                                    }
                                }
                                .tint(Color.sapphoPrimaryLight)
                                .accessibilityLabel("Chapter position")
                                .accessibilityValue("\(formatTime(max(0, chapterPosition))) of \(formatTime(chapterDuration))")

                                HStack {
                                    Text(formatTime(max(0, chapterPosition)))
                                        .accessibilityHidden(true)
                                    Spacer()
                                    Text("-" + formatTime(max(0, chapterDuration - chapterPosition)))
                                        .accessibilityHidden(true)
                                }
                                .font(.sapphoSmall)
                                .foregroundColor(.sapphoTextMuted)
                            } else {
                                // Full book slider
                                Slider(
                                    value: Binding(
                                        get: { isSeeking ? seekPosition : audioPlayer.position },
                                        set: { newValue in
                                            isSeeking = true
                                            seekPosition = newValue
                                        }
                                    ),
                                    in: 0...max(audioPlayer.duration, 1)
                                ) { editing in
                                    if !editing {
                                        Task {
                                            await audioPlayer.seek(to: seekPosition)
                                        }
                                        isSeeking = false
                                    }
                                }
                                .tint(Color.sapphoPrimaryLight)
                                .accessibilityLabel("Playback position")
                                .accessibilityValue("\(formatTime(audioPlayer.position)) of \(formatTime(audioPlayer.duration))")

                                HStack {
                                    Text(formatTime(audioPlayer.position))
                                        .accessibilityHidden(true)
                                    Spacer()
                                    Text("-" + formatTime(audioPlayer.duration - audioPlayer.position))
                                        .accessibilityHidden(true)
                                }
                                .font(.sapphoSmall)
                                .foregroundColor(.sapphoTextMuted)
                            }
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
                                    .foregroundColor(hasChapters ? .sapphoTextHigh : Color.sapphoDisabled)
                            }
                            .disabled(!hasChapters)
                            .frame(width: 48, height: 48)
                            .accessibilityLabel("Previous chapter")
                            .accessibilityHint(hasChapters ? "Double tap to go to previous chapter" : "No chapters available")

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
                            .accessibilityLabel("Skip back 10 seconds")

                            Spacer()

                            // Play/Pause
                            Button {
                                audioPlayer.togglePlayPause()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(audioPlayer.isPlaying
                                            ? Color.sapphoPlayingGreen
                                            : Color.sapphoPrimaryLight)
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
                            .accessibilityLabel(audioPlayer.isPlaying ? "Pause" : "Play")
                            .accessibilityHint(audioPlayer.isPlaying ? "Double tap to pause playback" : "Double tap to resume playback")

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
                            .accessibilityLabel("Skip forward 10 seconds")

                            Spacer()

                            // Next chapter
                            Button {
                                jumpToNextChapter()
                            } label: {
                                Image(systemName: "forward.end.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(hasChapters ? .sapphoTextHigh : Color.sapphoDisabled)
                            }
                            .disabled(!hasChapters)
                            .frame(width: 48, height: 48)
                            .accessibilityLabel("Next chapter")
                            .accessibilityHint(hasChapters ? "Double tap to go to next chapter" : "No chapters available")

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
                                        .foregroundColor(hasChapters ? .sapphoPrimary : Color.sapphoDisabled)
                                    Text(audioPlayer.currentChapter?.title ?? "Chapters")
                                        .font(.sapphoSmall)
                                        .foregroundColor(hasChapters ? .sapphoTextHigh : Color.sapphoDisabled)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .disabled(!hasChapters)
                            .accessibilityLabel("Chapters")
                            .accessibilityValue(audioPlayer.currentChapter?.title ?? "No chapter selected")
                            .accessibilityHint(hasChapters ? "Double tap to browse chapters" : "No chapters available")

                            // Speed
                            Button {
                                showSpeedPicker = true
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "speedometer")
                                        .font(.system(size: 20))
                                        .foregroundColor(.sapphoSecondary)
                                    Text(String(format: "%.2gx", audioPlayer.playbackSpeed))
                                        .font(.sapphoSmall)
                                        .foregroundColor(.sapphoTextHigh)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .accessibilityLabel("Playback speed")
                            .accessibilityValue(String(format: "%.2g times", audioPlayer.playbackSpeed))
                            .accessibilityHint("Double tap to change playback speed")

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
                            .accessibilityLabel("Sleep timer")
                            .accessibilityValue(audioPlayer.sleepTimerRemaining != nil ? "\(formatTime(audioPlayer.sleepTimerRemaining!)) remaining" : "Off")
                            .accessibilityHint("Double tap to set sleep timer")
                        }
                        .padding(.top, 8)

                    }
                    .padding(.vertical, 16)

                Spacer()
            }
            .offset(y: dragOffset)
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
                            dragOffset = 0
                        } else {
                            withAnimation(.interactiveSpring()) {
                                dragOffset = 0
                            }
                        }
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
                .accessibilityLabel("Decrease speed")
                .accessibilityHint("Double tap to decrease by 0.05")

                Text(displaySpeed)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.sapphoTextHigh)
                    .frame(minWidth: 100)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Current speed: \(displaySpeed)")

                Button {
                    adjustSpeed(by: 0.05)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.sapphoPrimary)
                }
                .accessibilityLabel("Increase speed")
                .accessibilityHint("Double tap to increase by 0.05")
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
                    .accessibilityLabel(String(format: "%.2g times speed", preset))
                    .accessibilityAddTraits(speed == preset ? .isSelected : [])
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
                    .accessibilityLabel("\(minutes) minutes")
                    .accessibilityHint("Double tap to set sleep timer for \(minutes) minutes")
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
                                .accessibilityHidden(true)
                        }
                    }
                }
                .listRowBackground(Color.sapphoSurface)
                .accessibilityLabel("\(chapter.title ?? "Chapter \(chapter.id)")\(chapter.duration != nil ? ", \(formatDuration(Int(chapter.duration!)))" : "")")
                .accessibilityValue(chapter.id == currentChapter?.id ? "Currently playing" : "")
                .accessibilityHint("Double tap to play this chapter")
            }
            .listStyle(.plain)
            .background(Color.sapphoBackground)
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

}

// MARK: - Playing Animation Bars
struct PlayingAnimationBars: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 3) {
                bar(time: time, speed: 5.0, minHeight: 3, maxHeight: 12, offset: 0)
                bar(time: time, speed: 4.0, minHeight: 3, maxHeight: 7, offset: 0.3)
                bar(time: time, speed: 5.5, minHeight: 3, maxHeight: 10, offset: 0.6)
            }
        }
        .frame(height: 12)
    }

    private func bar(time: Double, speed: Double, minHeight: CGFloat, maxHeight: CGFloat, offset: Double) -> some View {
        let wave = (sin((time + offset) * speed) + 1) / 2
        let height = minHeight + CGFloat(wave) * (maxHeight - minHeight)
        return RoundedRectangle(cornerRadius: 2)
            .fill(Color.sapphoPrimaryLight)
            .frame(width: 3, height: height)
    }
}

#Preview {
    PlayerView(showFullPlayer: .constant(true))
        .environment(AuthRepository())
        .environment(AudioPlayerService())
}
