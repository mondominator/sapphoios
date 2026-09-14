import CarPlay
import UIKit

/// Configures CPNowPlayingTemplate.shared with custom buttons for chapter navigation
/// and playback speed cycling.
@MainActor
final class CarPlayNowPlayingManager {

    private weak var audioPlayer: AudioPlayerService?
    private let speedSteps: [Float] = [1.0, 1.25, 1.5, 2.0]

    var template: CPNowPlayingTemplate {
        CPNowPlayingTemplate.shared
    }

    init(audioPlayer: AudioPlayerService) {
        self.audioPlayer = audioPlayer
        configureTemplate()
    }

    private func configureTemplate() {
        let nowPlaying = CPNowPlayingTemplate.shared

        // Disable optional buttons we don't need
        nowPlaying.isUpNextButtonEnabled = false
        nowPlaying.isAlbumArtistButtonEnabled = false

        // Build custom buttons
        let chapterBackButton = CPNowPlayingImageButton(
            image: UIImage(systemName: "backward.end.fill") ?? UIImage()
        ) { [weak self] _ in
            self?.jumpToPreviousChapter()
        }

        let chapterForwardButton = CPNowPlayingImageButton(
            image: UIImage(systemName: "forward.end.fill") ?? UIImage()
        ) { [weak self] _ in
            self?.jumpToNextChapter()
        }

        let speedButton = CPNowPlayingImageButton(
            image: UIImage(systemName: "gauge.with.needle.fill") ?? UIImage()
        ) { [weak self] _ in
            self?.cyclePlaybackSpeed()
        }

        // Road noise loses you a line far more often than it loses you a
        // chapter, so a short rewind earns its slot ahead of chapter-back.
        let backThirtyButton = CPNowPlayingImageButton(
            image: UIImage(systemName: "gobackward.30") ?? UIImage()
        ) { [weak self] _ in
            self?.audioPlayer?.skipBackward(seconds: 30)
        }

        // Sleep timer is a signature audiobook control and had no CarPlay
        // affordance at all -- you had to pick up the phone to set it.
        let sleepButton = CPNowPlayingImageButton(
            image: UIImage(systemName: "moon.zzz.fill") ?? UIImage()
        ) { [weak self] _ in
            self?.cycleSleepTimer()
        }

        nowPlaying.updateNowPlayingButtons([
            backThirtyButton,
            chapterBackButton,
            chapterForwardButton,
            speedButton,
            sleepButton
        ])
    }

    // MARK: - Sleep Timer

    /// CarPlay buttons cannot open a picker, so this cycles the common
    /// durations and wraps back to off. Mirrors the options the phone player
    /// offers rather than inventing a second set.
    private func cycleSleepTimer() {
        guard let audioPlayer = audioPlayer else { return }

        let steps: [Int] = [15, 30, 45, 60]
        let remaining = audioPlayer.sleepTimerRemaining

        guard let remaining = remaining, remaining > 0 else {
            audioPlayer.setSleepTimer(minutes: steps[0])
            return
        }

        let currentMinutes = Int((remaining / 60).rounded(.up))
        if let next = steps.first(where: { $0 > currentMinutes }) {
            audioPlayer.setSleepTimer(minutes: next)
        } else {
            audioPlayer.cancelSleepTimer()
        }
    }

    // MARK: - Chapter Navigation

    private func jumpToPreviousChapter() {
        guard let audioPlayer = audioPlayer,
              let chapters = audioPlayer.currentAudiobook?.chapters,
              !chapters.isEmpty else { return }

        let currentPosition = audioPlayer.position

        // Find the previous chapter: the last chapter whose startTime is before
        // (currentPosition - 2 seconds) to avoid getting stuck at current chapter boundary
        let threshold = max(currentPosition - 2, 0)
        if let previousChapter = chapters.last(where: { $0.startTime < threshold }) {
            audioPlayer.jumpToChapter(previousChapter)
        } else {
            // Already at or before first chapter, jump to beginning
            audioPlayer.jumpToChapter(chapters[0])
        }
    }

    private func jumpToNextChapter() {
        guard let audioPlayer = audioPlayer,
              let chapters = audioPlayer.currentAudiobook?.chapters,
              !chapters.isEmpty else { return }

        let currentPosition = audioPlayer.position

        // Find the next chapter whose startTime is after current position
        if let nextChapter = chapters.first(where: { $0.startTime > currentPosition }) {
            audioPlayer.jumpToChapter(nextChapter)
        }
        // If no next chapter, do nothing (already in last chapter)
    }

    // MARK: - Speed Cycling

    private func cyclePlaybackSpeed() {
        guard let audioPlayer = audioPlayer else { return }

        let currentSpeed = audioPlayer.playbackSpeed
        // Find current speed in the steps array, then move to next
        if let currentIndex = speedSteps.firstIndex(where: { abs($0 - currentSpeed) < 0.01 }) {
            let nextIndex = (currentIndex + 1) % speedSteps.count
            audioPlayer.setPlaybackSpeed(speedSteps[nextIndex])
        } else {
            // Current speed not in list, reset to 1.0
            audioPlayer.setPlaybackSpeed(1.0)
        }
    }
}
