import Foundation

/// Shared time formatting utilities used across the app.
///
/// Two formatting styles:
/// - `formatTime`: Clock-style display (e.g. "1:23:45" or "3:05") for player positions and countdowns
/// - `formatDuration`: Human-readable display (e.g. "2h 15m" or "45m") for metadata and labels

/// Formats seconds into clock-style time string (H:MM:SS or M:SS).
/// Used for player position, remaining time, and seek bar labels.
func formatTime(_ seconds: TimeInterval) -> String {
    let totalSeconds = Int(seconds)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}

/// Formats seconds into clock-style time string (H:MM:SS or M:SS).
/// Convenience overload accepting Int.
func formatTime(_ seconds: Int) -> String {
    formatTime(TimeInterval(seconds))
}

/// Formats seconds into a human-readable duration string (e.g. "2h 15m" or "45m").
/// Used for audiobook total duration, chapter length, and metadata labels.
func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60

    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }
    return "\(minutes)m"
}
