import SwiftUI

/// "Listened to Golden Son · Today 6:12 PM" on one line: the book title
/// truncates with "…" and the timestamp always stays whole.
struct LastListenLine: View {
    let activity: ListeningActivity?

    var body: some View {
        Group {
            if let activity {
                HStack(spacing: 4) {
                    Text(activity.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("· \(ListeningActivity.timestamp(activity.date))")
                        .lineLimit(1)
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
            } else {
                Text(ListeningActivity.summary(nil))
                    .lineLimit(1)
            }
        }
        .font(.sapphoSmall)
        .foregroundColor(.sapphoTextMuted)
    }
}

/// Read-only account and activity details for one user (Admin > Users).
struct AdminUserDetailView: View {
    let user: AdminUser

    var body: some View {
        List {
            Section("Account") {
                LabeledContent("Username", value: user.username)
                if let email = user.email, !email.isEmpty {
                    LabeledContent("Email", value: email)
                }
                if let displayName = user.displayName, !displayName.isEmpty {
                    LabeledContent("Display name", value: displayName)
                }
                LabeledContent("Role", value: user.isAdminUser ? "Admin" : "User")
                LabeledContent("Status", value: user.isAccountDisabled ? "Disabled" : "Active")
                if let created = user.createdDate {
                    LabeledContent("Created", value: created.formatted(date: .abbreviated, time: .omitted))
                }
            }

            if user.reportsActivity {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last listened")
                            .foregroundColor(.sapphoTextHigh)
                        // Full text here: room to wrap a long title.
                        Text(ListeningActivity.summary(user.lastListen))
                            .font(.sapphoSmall)
                            .foregroundColor(.sapphoTextMuted)
                    }
                    LabeledContent("Last login") {
                        Text(ListeningActivity.lastLoginLabel(user.lastLoginDate))
                            .foregroundColor(.sapphoTextMuted)
                    }
                } header: {
                    Text("Activity")
                } footer: {
                    Text("Logins are recorded from server 0.16.5 on, so older accounts show “Not recorded yet” until their next sign-in.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.sapphoBackground)
        .navigationTitle(user.username)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
