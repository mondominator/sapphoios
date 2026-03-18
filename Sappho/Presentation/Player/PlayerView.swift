import SwiftUI
import AVKit

struct PlayerView: View {
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Binding var showFullPlayer: Bool

    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = 30
    @AppStorage("skipBackwardSeconds") private var skipBackwardSeconds = 15

    @AppStorage("showChapterProgress") private var showChapterProgress = true

    @State private var showSpeedPicker = false
    @State private var showSleepTimer = false
    @State private var showChapters = false
    @State private var dragOffset: CGFloat = 0
    @State private var isPulsing = false
    @State private var isSeeking = false
    @State private var seekPosition: TimeInterval = 0
    @State private var gradientPhase: CGFloat = 0

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
                                    .lineLimit(1)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Progress Slider
                        VStack(spacing: 8) {
                            if showChapterProgress, let chapter = audioPlayer.currentChapter {
                                // Chapter-scoped progress
                                let chapterStart = chapter.startTime
                                let chapterDuration = max(chapter.duration ?? (audioPlayer.duration - chapterStart), 1)
                                let chapterPosition = max(0, audioPlayer.position - chapterStart)
                                let progressPercent = isSeeking
                                    ? seekPosition / chapterDuration
                                    : min(1, chapterPosition / chapterDuration)

                                PlayerProgressBar(
                                    progressPercent: progressPercent,
                                    isPlaying: audioPlayer.isPlaying,
                                    gradientPhase: gradientPhase
                                ) { percent in
                                    isSeeking = true
                                    seekPosition = percent * chapterDuration
                                } onSeekEnd: { percent in
                                    let target = chapterStart + percent * chapterDuration
                                    Task { await audioPlayer.seek(to: target) }
                                    isSeeking = false
                                }
                                .accessibilityLabel("Chapter position")
                                .accessibilityValue("\(formatTime(chapterPosition)) of \(formatTime(chapterDuration))")

                                HStack {
                                    Text(formatTime(chapterPosition))
                                        .accessibilityHidden(true)
                                    Spacer()
                                    Text("-" + formatTime(max(0, chapterDuration - chapterPosition)))
                                        .accessibilityHidden(true)
                                }
                                .font(.sapphoSmall)
                                .foregroundColor(.sapphoTextMuted)
                            } else {
                                // Full book progress
                                let progressPercent = isSeeking
                                    ? (audioPlayer.duration > 0 ? seekPosition / audioPlayer.duration : 0)
                                    : (audioPlayer.duration > 0 ? audioPlayer.position / audioPlayer.duration : 0)

                                PlayerProgressBar(
                                    progressPercent: progressPercent,
                                    isPlaying: audioPlayer.isPlaying,
                                    gradientPhase: gradientPhase
                                ) { percent in
                                    isSeeking = true
                                    seekPosition = percent * max(audioPlayer.duration, 1)
                                } onSeekEnd: { percent in
                                    let target = percent * max(audioPlayer.duration, 1)
                                    Task { await audioPlayer.seek(to: target) }
                                    isSeeking = false
                                }
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
                        .onAppear {
                            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                                gradientPhase = 1.0
                            }
                        }

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
                                    Text("Chapters")
                                        .font(.system(size: 11))
                                        .foregroundColor(hasChapters ? .sapphoTextHigh : Color.sapphoDisabled)
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
                                    if audioPlayer.sleepAtEndOfChapter {
                                        Image(systemName: "moon.zzz.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(.sapphoWarning)
                                        Text("Chapter")
                                            .font(.sapphoSmall)
                                            .foregroundColor(.sapphoWarning)
                                    } else if let remaining = audioPlayer.sleepTimerRemaining, remaining > 0 {
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
                    hasChapters: hasChapters,
                    isEndOfChapter: audioPlayer.sleepAtEndOfChapter,
                    onSet: { minutes in
                        audioPlayer.setSleepTimer(minutes: minutes)
                    },
                    onEndOfChapter: {
                        audioPlayer.setSleepTimerEndOfChapter()
                    },
                    onCancel: {
                        audioPlayer.cancelSleepTimer()
                    }
                )
                .presentationDetents([.height(450)])
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

    private var displaySpeed: String {
        if speed == Float(Int(speed)) {
            return String(format: "%.0fx", speed)
        } else {
            return String(format: "%.2gx", speed)
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

            // Current speed display
            Text(displaySpeed)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.sapphoTextHigh)
                .contentTransition(.numericText())

            // Slider
            VStack(spacing: 8) {
                Slider(
                    value: $speed,
                    in: 0.5...3.0,
                    step: 0.05
                ) {
                    Text("Speed")
                } onEditingChanged: { editing in
                    if !editing {
                        onSelect(speed)
                    }
                }
                .tint(.sapphoPrimary)
                .padding(.horizontal, 16)
                .onChange(of: speed) { _, newSpeed in
                    onSelect(newSpeed)
                }

                HStack {
                    Text("0.5x")
                    Spacer()
                    Text("3x")
                }
                .font(.sapphoSmall)
                .foregroundColor(.sapphoTextMuted)
                .padding(.horizontal, 16)
            }

            Spacer()
        }
        .background(Color.sapphoBackground)
    }
}

// MARK: - Sleep Timer Sheet
struct SleepTimerSheet: View {
    let currentRemaining: TimeInterval?
    let hasChapters: Bool
    let isEndOfChapter: Bool
    let onSet: (Int) -> Void
    let onEndOfChapter: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var customMinutes: String = ""
    @FocusState private var customFieldFocused: Bool

    private let options = [5, 10, 15, 30, 45, 60, 90, 120]

    var body: some View {
        VStack(spacing: 20) {
            // Handle
            Capsule()
                .fill(Color.sapphoTextMuted.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            Text("Sleep Timer")
                .font(.sapphoHeadline)
                .foregroundColor(.sapphoTextHigh)

            if let remaining = currentRemaining, remaining > 0 {
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
            } else if isEndOfChapter {
                // End of chapter active
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.sapphoWarning)
                    Text("End of chapter")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.sapphoWarning)
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

            ScrollView {
                VStack(spacing: 10) {
                    // End of chapter option
                    if hasChapters {
                        Button {
                            onEndOfChapter()
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "bookmark.fill")
                                    .foregroundColor(.sapphoWarning)
                                Text("End of chapter")
                                    .foregroundColor(.sapphoTextHigh)
                                Spacer()
                                if isEndOfChapter {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.sapphoWarning)
                                }
                            }
                            .font(.sapphoBody)
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .background(isEndOfChapter ? Color.sapphoWarning.opacity(0.15) : Color.sapphoSurface)
                            .cornerRadius(8)
                        }
                    }

                    // Preset options
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 10) {
                        ForEach(options, id: \.self) { minutes in
                            Button {
                                onSet(minutes)
                                dismiss()
                            } label: {
                                Text(minutes >= 60 ? "\(minutes / 60)h\(minutes % 60 > 0 ? " \(minutes % 60)m" : "")" : "\(minutes) min")
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

                    // Custom timer
                    HStack(spacing: 10) {
                        TextField("Custom", text: $customMinutes)
                            .keyboardType(.numberPad)
                            .font(.sapphoBody)
                            .foregroundColor(.sapphoTextHigh)
                            .padding(.horizontal, 12)
                            .frame(height: 40)
                            .background(Color.sapphoSurface)
                            .cornerRadius(8)
                            .focused($customFieldFocused)

                        Button {
                            if let mins = Int(customMinutes), mins > 0 {
                                onSet(mins)
                                dismiss()
                            }
                        } label: {
                            Text("Set")
                                .font(.sapphoBody)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .frame(height: 40)
                                .background(customMinutes.isEmpty ? Color.sapphoSurface : Color.sapphoPrimary)
                                .cornerRadius(8)
                        }
                        .disabled(Int(customMinutes) == nil || Int(customMinutes)! <= 0)
                    }
                }
                .padding(.horizontal, 16)
            }
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
            ScrollViewReader { proxy in
                List(chapters) { chapter in
                    let isCurrent = chapter.id == currentChapter?.id
                    Button {
                        onSelect(chapter)
                    } label: {
                        HStack {
                            if isCurrent {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.sapphoPrimary)
                                    .accessibilityHidden(true)
                            }

                            Text(chapter.title ?? "Chapter \(chapter.id)")
                                .font(.sapphoBody)
                                .foregroundColor(isCurrent ? .sapphoPrimary : .sapphoTextHigh)
                                .lineLimit(2)

                            Spacer()

                            if let duration = chapter.duration {
                                Text(formatDuration(Int(duration)))
                                    .font(.sapphoSmall)
                                    .foregroundColor(.sapphoTextMuted)
                            }
                        }
                    }
                    .listRowBackground(
                        isCurrent
                            ? Color.sapphoPrimary.opacity(0.12)
                            : Color.sapphoSurface
                    )
                    .id(chapter.id)
                    .accessibilityLabel("\(chapter.title ?? "Chapter \(chapter.id)")\(chapter.duration != nil ? ", \(formatDuration(Int(chapter.duration!)))" : "")")
                    .accessibilityValue(isCurrent ? "Currently playing" : "")
                    .accessibilityHint("Double tap to play this chapter")
                }
                .listStyle(.plain)
                .background(Color.sapphoBackground)
                .navigationTitle("Chapters")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .onAppear {
                    if let currentId = currentChapter?.id {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(currentId, anchor: .center)
                            }
                        }
                    }
                }
            }
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

// MARK: - Player Progress Bar
struct PlayerProgressBar: View {
    let progressPercent: Double
    let isPlaying: Bool
    let gradientPhase: CGFloat
    let onSeekChanged: (Double) -> Void
    let onSeekEnd: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progressWidth = width * max(0, min(1, progressPercent))

            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 4)

                // Animated gradient fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        isPlaying
                            ? LinearGradient(
                                colors: [
                                    Color.sapphoPrimaryLight,
                                    Color.sapphoPlayingGreen,
                                    Color.sapphoPrimaryLight
                                ],
                                startPoint: UnitPoint(x: gradientPhase - 0.5, y: 0.5),
                                endPoint: UnitPoint(x: gradientPhase + 0.5, y: 0.5)
                            )
                            : LinearGradient(
                                colors: [Color.sapphoPrimaryLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                    )
                    .frame(width: progressWidth, height: 4)

                // Glowing thumb
                if progressPercent > 0 {
                    Circle()
                        .fill(isPlaying ? Color.sapphoPlayingGreen : Color.sapphoPrimaryLight)
                        .frame(width: 14, height: 14)
                        .shadow(color: (isPlaying ? Color.sapphoPlayingGreen : Color.sapphoPrimaryLight).opacity(0.6), radius: isPlaying ? 8 : 2)
                        .offset(x: progressWidth - 7)
                }
            }
            .frame(height: 14)
            .contentShape(Rectangle().inset(by: -10))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let percent = max(0, min(1, value.location.x / width))
                        onSeekChanged(percent)
                    }
                    .onEnded { value in
                        let percent = max(0, min(1, value.location.x / width))
                        onSeekEnd(percent)
                    }
            )
        }
        .frame(height: 14)
    }
}

// MARK: - Marquee UILabel (UIKit-based for reliable clipping and scrolling)
struct MarqueeUILabel: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let textColor: UIColor

    func makeUIView(context: Context) -> MarqueeContainerView {
        let view = MarqueeContainerView()
        view.fontSize = fontSize
        view.textColor = textColor
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ view: MarqueeContainerView, context: Context) {
        view.textColor = textColor
        view.setText(text)
    }
}

class MarqueeContainerView: UIView {
    var fontSize: CGFloat = 11
    var textColor: UIColor = .white {
        didSet {
            label1.textColor = textColor
            label2.textColor = textColor
        }
    }

    private let label1 = UILabel()
    private let label2 = UILabel()
    private var displayLink: CADisplayLink?
    private var scrollOffset: CGFloat = 0
    private let gap: CGFloat = 40
    private let speed: CGFloat = 25 // points per second
    private var lastTimestamp: CFTimeInterval = 0
    private var currentText: String = ""

    private var needsScroll: Bool {
        label1.intrinsicContentSize.width > bounds.width && bounds.width > 0
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLabels()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLabels()
    }

    private func setupLabels() {
        label1.numberOfLines = 1
        label2.numberOfLines = 1
        addSubview(label1)
        addSubview(label2)
        label2.isHidden = true
    }

    func setText(_ text: String) {
        let font = UIFont.systemFont(ofSize: fontSize)
        label1.font = font
        label2.font = font
        label1.text = text
        label2.text = text
        if text != currentText {
            currentText = text
            scrollOffset = 0
            lastTimestamp = 0
            displayLink?.invalidate()
            displayLink = nil
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let textSize = label1.intrinsicContentSize

        if needsScroll {
            if displayLink == nil {
                label1.frame = CGRect(x: 0, y: 0, width: textSize.width, height: bounds.height)
                label2.frame = CGRect(x: textSize.width + gap, y: 0, width: textSize.width, height: bounds.height)
                label2.isHidden = false
                startScrolling()
            }
        } else {
            label2.isHidden = true
            label1.frame = bounds
            stopScrolling()
        }
    }

    private func startScrolling() {
        guard displayLink == nil else { return }
        lastTimestamp = 0
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopScrolling() {
        displayLink?.invalidate()
        displayLink = nil
        scrollOffset = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            return
        }
        let dt = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp

        scrollOffset -= speed * CGFloat(dt)

        let textWidth = label1.intrinsicContentSize.width
        let totalCycle = textWidth + gap
        if scrollOffset <= -totalCycle {
            scrollOffset += totalCycle
        }
        label1.frame.origin.x = scrollOffset
        label2.frame.origin.x = scrollOffset + textWidth + gap
    }
}

#Preview {
    PlayerView(showFullPlayer: .constant(true))
        .environment(AuthRepository())
        .environment(AudioPlayerService())
}
