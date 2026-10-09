import SwiftUI

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
                    activityRow("Last activity", date: user.lastActivityDate, nilText: "No activity yet")
                    activityRow("Last listened", date: user.lastListenedDate, nilText: "Never")
                    activityRow("Last login", date: user.lastLoginDate, nilText: UserActivity.lastLoginLabel(nil))
                } header: {
                    Text("Activity")
                } footer: {
                    Text("Last activity is the latest of listening and app use. Logins are recorded from server 0.16.5 on, so older accounts show “Not recorded yet” until their next sign-in.")
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

    private func activityRow(_ title: String, date: Date?, nilText: String) -> some View {
        LabeledContent(title) {
            if let date {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(UserActivity.relative(date))
                        .foregroundColor(.sapphoTextHigh)
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.sapphoSmall)
                        .foregroundColor(.sapphoTextMuted)
                }
            } else {
                Text(nilText)
                    .foregroundColor(.sapphoTextMuted)
            }
        }
    }
}
