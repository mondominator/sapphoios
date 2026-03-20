import SwiftUI

struct ListeningHistorySheet: View {
    let audiobookId: Int
    let onSeek: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sapphoAPI) private var api
    @State private var sessions: [ListeningSession] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sessions.isEmpty {
                    Text("No listening history yet")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(sessions) { session in
                        Button {
                            onSeek(session.startPosition)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formatSessionDate(session.startedAt))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack(spacing: 4) {
                                    Text(formatPosition(session.startPosition))
                                    Text("\u{2192}")
                                        .foregroundColor(.secondary)
                                    if let end = session.endPosition {
                                        Text(formatPosition(end))
                                        let duration = (end - session.startPosition) / 60
                                        Text("(\(duration) min)")
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("In progress")
                                            .foregroundColor(.orange)
                                    }
                                }
                                .font(.body)

                                if let device = session.deviceName {
                                    Text(device)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Listening History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            do {
                sessions = try await api?.getListeningSessions(audiobookId: audiobookId) ?? []
            } catch { }
            isLoading = false
        }
    }

    private func formatPosition(_ totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func formatSessionDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateStr) {
            let display = DateFormatter()
            display.dateFormat = "MMM d, h:mm a"
            return display.string(from: date)
        }
        // Try without fractional seconds
        let basic = ISO8601DateFormatter()
        if let date = basic.date(from: dateStr) {
            let display = DateFormatter()
            display.dateFormat = "MMM d, h:mm a"
            return display.string(from: date)
        }
        return dateStr
    }
}
