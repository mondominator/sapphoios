import SwiftUI

struct NotificationPanel: View {
    @Environment(\.sapphoAPI) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var notifications: [NotificationItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var onMarkedRead: () -> Void = {}

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sapphoBackground.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(.sapphoPrimary)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.sapphoIconXLarge)
                            .foregroundColor(.sapphoTextMuted)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.sapphoTextMuted)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await loadNotifications() }
                        }
                        .foregroundColor(.sapphoPrimary)
                    }
                    .padding()
                } else if notifications.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.slash")
                            .font(.sapphoIconXLarge)
                            .foregroundColor(.sapphoTextMuted)
                        Text("No notifications yet")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("You'll be notified when new audiobooks are added or other events occur.")
                            .font(.subheadline)
                            .foregroundColor(.sapphoTextMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(notifications) { notification in
                                notificationRow(notification)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        Task {
                                            await markRead(notification)
                                        }
                                    }

                                Divider()
                                    .background(Color.white.opacity(0.06))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.sapphoSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.sapphoPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if notifications.contains(where: { $0.isUnread }) {
                        Button("Mark all read") {
                            Task { await markAllRead() }
                        }
                        .font(.subheadline)
                        .foregroundColor(.sapphoPrimary)
                    }
                }
            }
        }
        .task {
            await loadNotifications()
        }
    }

    // MARK: - Notification Row

    @ViewBuilder
    private func notificationRow(_ notification: NotificationItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Unread indicator
            Circle()
                .fill(notification.isUnread ? Color.sapphoPrimary : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            // Type icon
            Image(systemName: iconForType(notification.type))
                .font(.sapphoIconTiny)
                .foregroundColor(colorForType(notification.type))
                .frame(width: 32, height: 32)
                .background(colorForType(notification.type).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(notification.title)
                    .font(.subheadline)
                    .fontWeight(notification.isUnread ? .semibold : .regular)
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text(notification.message)
                    .font(.caption)
                    .foregroundColor(.sapphoTextMuted)
                    .lineLimit(3)

                Text(relativeDate(from: notification.createdAt))
                    .font(.caption2)
                    .foregroundColor(.sapphoTextMuted.opacity(0.7))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(notification.isUnread ? Color.sapphoPrimary.opacity(0.05) : Color.clear)
    }

    // MARK: - Helpers

    private func iconForType(_ type: String) -> String {
        switch type {
        case "new_audiobook":
            return "book.fill"
        case "collection_shared":
            return "folder.fill"
        case "new_review":
            return "star.fill"
        case "system":
            return "gearshape.fill"
        default:
            return "bell.fill"
        }
    }

    private func colorForType(_ type: String) -> Color {
        switch type {
        case "new_audiobook":
            return .sapphoPrimary
        case "collection_shared":
            return .orange
        case "new_review":
            return .yellow
        case "system":
            return .sapphoTextMuted
        default:
            return .sapphoPrimary
        }
    }

    private func relativeDate(from dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Try with fractional seconds first, then without
        var date = formatter.date(from: dateString)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: dateString)
        }

        guard let parsed = date else { return dateString }

        let now = Date()
        let interval = now.timeIntervalSince(parsed)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            return dateFormatter.string(from: parsed)
        }
    }

    // MARK: - Actions

    private func loadNotifications() async {
        isLoading = true
        errorMessage = nil
        do {
            notifications = try await api?.getNotifications() ?? []
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func markRead(_ notification: NotificationItem) async {
        guard notification.isUnread else { return }
        do {
            try await api?.markNotificationRead(id: notification.id)
            if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
                // Reload to get updated state
                if let updated = try? await api?.getNotifications() {
                    notifications = updated
                }
            }
            onMarkedRead()
        } catch {
            // Silently fail - non-critical
        }
    }

    private func markAllRead() async {
        do {
            try await api?.markAllNotificationsRead()
            if let updated = try? await api?.getNotifications() {
                notifications = updated
            }
            onMarkedRead()
        } catch {
            // Silently fail
        }
    }
}
