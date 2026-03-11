import SwiftUI

struct ProfileView: View {
    @Environment(AuthRepository.self) private var authRepository
    @Environment(\.sapphoAPI) private var api

    @State private var stats: UserStats?
    @State private var isLoading = true
    @State private var showLogoutConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // User Info Card
                    if let user = authRepository.currentUser {
                        VStack(spacing: 16) {
                            // Avatar
                            AsyncImage(url: api?.avatarURL()) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle()
                                    .fill(Color.sapphoSurface)
                                    .overlay(
                                        Text(String(user.username?.prefix(1).uppercased() ?? "?"))
                                            .font(.sapphoTitle)
                                            .foregroundColor(.sapphoTextMuted)
                                    )
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())

                            // Name
                            Text(user.displayName ?? user.username ?? "User")
                                .font(.sapphoHeadline)
                                .foregroundColor(.sapphoTextHigh)

                            // Email
                            if let email = user.email {
                                Text(email)
                                    .font(.sapphoCaption)
                                    .foregroundColor(.sapphoTextMuted)
                            }

                            // Admin badge
                            if user.isAdminUser {
                                Text("Admin")
                                    .font(.sapphoSmall)
                                    .foregroundColor(.sapphoPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.sapphoPrimary.opacity(0.2))
                                    .cornerRadius(12)
                            }

                            // Edit Profile button
                            NavigationLink {
                                ProfileEditView()
                            } label: {
                                Text("Edit Profile")
                                    .font(.sapphoCaption)
                                    .foregroundColor(.sapphoPrimary)
                            }
                            .padding(.top, 8)
                        }
                        .padding(.vertical, 24)
                    }

                    // Stats
                    if let stats = stats {
                        VStack(spacing: 16) {
                            Text("Listening Stats")
                                .font(.sapphoHeadline)
                                .foregroundColor(.sapphoTextHigh)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 16) {
                                StatCard(title: "Books Started", value: "\(stats.booksStarted)")
                                StatCard(title: "Books Completed", value: "\(stats.booksCompleted)")
                                StatCard(title: "Listen Time", value: formatDuration(stats.totalListenTime))
                                StatCard(title: "Current Streak", value: "\(stats.currentStreak) days")
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Quick Links
                    VStack(spacing: 0) {
                        NavigationLink {
                            FavoritesView()
                        } label: {
                            SettingsRow(icon: "heart.fill", title: "Favorites")
                        }

                        Divider()
                            .background(Color.sapphoSurface)

                        NavigationLink {
                            ReadingListView()
                        } label: {
                            SettingsRow(icon: "list.bullet", title: "Up Next")
                        }
                    }
                    .background(Color.sapphoSurface)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)

                    // Settings Links
                    VStack(spacing: 0) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            SettingsRow(icon: "gear", title: "Settings")
                        }

                        Divider()
                            .background(Color.sapphoSurface)

                        NavigationLink {
                            DownloadsView()
                        } label: {
                            SettingsRow(icon: "arrow.down.circle", title: "Downloads")
                        }

                        if authRepository.currentUser?.isAdminUser == true {
                            Divider()
                                .background(Color.sapphoSurface)

                            NavigationLink {
                                AdminView()
                            } label: {
                                SettingsRow(icon: "wrench.and.screwdriver", title: "Admin")
                            }
                        }
                    }
                    .background(Color.sapphoSurface)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)

                    // Logout Button
                    Button {
                        showLogoutConfirmation = true
                    } label: {
                        Text("Logout")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SapphoSecondaryButtonStyle())
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    // Server Info
                    if let serverURL = authRepository.serverURL {
                        Text("Connected to: \(serverURL.host ?? serverURL.absoluteString)")
                            .font(.sapphoSmall)
                            .foregroundColor(.sapphoTextMuted)
                            .padding(.top, 8)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(Color.sapphoBackground)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("Logout", isPresented: $showLogoutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Logout", role: .destructive) {
                    authRepository.clear()
                }
            } message: {
                Text("Are you sure you want to logout?")
            }
        }
        .task {
            await loadStats()
        }
    }

    private func loadStats() async {
        do {
            stats = try await api?.getProfileStats()
        } catch {
            print("Failed to load stats: \(error)")
        }
        isLoading = false
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        if hours >= 24 {
            let days = hours / 24
            return "\(days)d"
        }
        return "\(hours)h"
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.sapphoHeadline)
                .foregroundColor(.sapphoPrimary)

            Text(title)
                .font(.sapphoSmall)
                .foregroundColor(.sapphoTextMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.sapphoSurface)
        .cornerRadius(12)
    }
}

// MARK: - Settings Row
struct SettingsRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.sapphoPrimary)
                .frame(width: 24)

            Text(title)
                .font(.sapphoBody)
                .foregroundColor(.sapphoTextHigh)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.sapphoTextMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = 30
    @AppStorage("skipBackwardSeconds") private var skipBackwardSeconds = 15
    @AppStorage("defaultPlaybackSpeed") private var defaultPlaybackSpeed = 1.0
    @AppStorage("autoSleepTimer") private var autoSleepTimer = false
    @AppStorage("sleepTimerMinutes") private var sleepTimerMinutes = 30
    @AppStorage("wifiOnlyDownloads") private var wifiOnlyDownloads = true
    @AppStorage("autoDownloadSeries") private var autoDownloadSeries = false

    var body: some View {
        Form {
            // Playback Settings
            Section("Playback") {
                Picker("Skip Forward", selection: $skipForwardSeconds) {
                    Text("10 seconds").tag(10)
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("45 seconds").tag(45)
                    Text("60 seconds").tag(60)
                }

                Picker("Skip Backward", selection: $skipBackwardSeconds) {
                    Text("10 seconds").tag(10)
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("45 seconds").tag(45)
                    Text("60 seconds").tag(60)
                }

                Picker("Default Speed", selection: $defaultPlaybackSpeed) {
                    Text("0.5x").tag(0.5)
                    Text("0.75x").tag(0.75)
                    Text("1.0x").tag(1.0)
                    Text("1.25x").tag(1.25)
                    Text("1.5x").tag(1.5)
                    Text("1.75x").tag(1.75)
                    Text("2.0x").tag(2.0)
                }
            }

            // Sleep Timer Settings
            Section("Sleep Timer") {
                Toggle("Auto Sleep Timer", isOn: $autoSleepTimer)

                if autoSleepTimer {
                    Picker("Default Duration", selection: $sleepTimerMinutes) {
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("45 minutes").tag(45)
                        Text("60 minutes").tag(60)
                        Text("90 minutes").tag(90)
                    }
                }
            }

            // Download Settings
            Section("Downloads") {
                Toggle("Wi-Fi Only Downloads", isOn: $wifiOnlyDownloads)
                Toggle("Auto-download Series", isOn: $autoDownloadSeries)
            }

            // About
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                        .foregroundColor(.sapphoTextMuted)
                }

                HStack {
                    Text("Build")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
                        .foregroundColor(.sapphoTextMuted)
                }

                Link(destination: URL(string: "https://github.com/mondominator/sappho")!) {
                    HStack {
                        Text("View on GitHub")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.sapphoTextMuted)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.sapphoBackground)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

struct DownloadsView: View {
    @Environment(\.sapphoAPI) private var api
    @State private var downloadedBooks: [Audiobook] = []
    @State private var isLoading = true

    private var downloadManager: DownloadManager { DownloadManager.shared }

    var body: some View {
        Group {
            if isLoading {
                LoadingView()
            } else if downloadedBooks.isEmpty {
                VStack(spacing: 16) {
                    EmptyStateView(
                        icon: "arrow.down.circle",
                        title: "No Downloads",
                        message: "Downloaded audiobooks will appear here for offline listening."
                    )
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Storage info
                        HStack {
                            Image(systemName: "internaldrive")
                                .foregroundColor(.sapphoPrimary)
                            Text("Using \(formatSize(downloadManager.totalDownloadSize()))")
                                .font(.sapphoCaption)
                                .foregroundColor(.sapphoTextMuted)

                            Spacer()

                            Button("Clear All") {
                                downloadManager.clearAllDownloads()
                                loadDownloads()
                            }
                            .font(.sapphoCaption)
                            .foregroundColor(.sapphoError)
                        }
                        .padding(.horizontal, 16)

                        LazyVStack(spacing: 12) {
                            ForEach(downloadedBooks) { audiobook in
                                NavigationLink {
                                    AudiobookDetailView(audiobook: audiobook)
                                } label: {
                                    DownloadedBookRow(
                                        audiobook: audiobook,
                                        onDelete: {
                                            downloadManager.removeDownload(audiobookId: audiobook.id)
                                            loadDownloads()
                                        }
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 16)
                    .padding(.bottom, 100)
                }
            }
        }
        .background(Color.sapphoBackground)
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await fetchDownloadedBooks()
        }
    }

    private func loadDownloads() {
        Task {
            await fetchDownloadedBooks()
        }
    }

    private func fetchDownloadedBooks() async {
        isLoading = downloadedBooks.isEmpty

        // Get list of downloaded audiobook IDs
        let downloadedIds = downloadManager.downloads.compactMap { (id, state) -> Int? in
            if case .downloaded = state {
                return id
            }
            return nil
        }

        guard !downloadedIds.isEmpty else {
            downloadedBooks = []
            isLoading = false
            return
        }

        // Fetch audiobook details for each downloaded ID
        do {
            let allBooks = try await api?.getAudiobooks() ?? []
            downloadedBooks = allBooks.filter { downloadedIds.contains($0.id) }
        } catch {
            print("Failed to fetch audiobooks: \(error)")
        }

        isLoading = false
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct DownloadedBookRow: View {
    let audiobook: Audiobook
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Cover
            CoverImage(audiobookId: audiobook.id)
                .frame(width: 60, height: 85)
                .cornerRadius(8)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(audiobook.title)
                    .font(.sapphoSubheadline)
                    .foregroundColor(.sapphoTextHigh)
                    .lineLimit(2)

                if let author = audiobook.author {
                    Text(author)
                        .font(.sapphoSmall)
                        .foregroundColor(.sapphoTextMuted)
                        .lineLimit(1)
                }

                if let duration = audiobook.duration {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(formatDuration(duration))
                            .font(.sapphoSmall)
                    }
                    .foregroundColor(.sapphoTextMuted)
                }

                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                    Text("Downloaded")
                        .font(.sapphoSmall)
                }
                .foregroundColor(.sapphoSuccess)
            }

            Spacer()

            // Delete button
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundColor(.sapphoError)
            }
            .buttonStyle(.plain)
            .padding(8)

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.sapphoTextMuted)
        }
        .padding(12)
        .background(Color.sapphoSurface)
        .cornerRadius(12)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

struct AdminView: View {
    @Environment(\.sapphoAPI) private var api
    @State private var users: [AdminUser] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCreateUserSheet = false
    @State private var isScanning = false
    @State private var scanMessage: String?

    var body: some View {
        List {
            // Library Management
            Section("Library") {
                Button {
                    Task { await scanLibrary() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.sapphoPrimary)
                        Text("Scan for New Books")
                        Spacer()
                        if isScanning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isScanning)

                Button {
                    Task { await forceRescan() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.sapphoWarning)
                        Text("Force Full Rescan")
                        Spacer()
                        if isScanning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isScanning)

                if let message = scanMessage {
                    Text(message)
                        .font(.sapphoSmall)
                        .foregroundColor(.sapphoSuccess)
                }
            }

            // User Management
            Section("Users") {
                Button {
                    showCreateUserSheet = true
                } label: {
                    HStack {
                        Image(systemName: "person.badge.plus")
                            .foregroundColor(.sapphoPrimary)
                        Text("Add New User")
                    }
                }

                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading users...")
                            .foregroundColor(.sapphoTextMuted)
                    }
                } else {
                    ForEach(users) { user in
                        AdminUserRow(user: user, onDelete: {
                            Task { await deleteUser(user.id) }
                        })
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.sapphoBackground)
        .navigationTitle("Admin")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showCreateUserSheet) {
            CreateUserSheet(onCreate: { username, password, isAdmin in
                Task {
                    await createUser(username: username, password: password, isAdmin: isAdmin)
                }
            })
        }
        .task {
            await loadUsers()
        }
    }

    private func loadUsers() async {
        isLoading = true
        do {
            users = try await api?.getUsers() ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func createUser(username: String, password: String, isAdmin: Bool) async {
        do {
            let _ = try await api?.createUser(username: username, password: password, isAdmin: isAdmin)
            await loadUsers()
            showCreateUserSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteUser(_ id: Int) async {
        do {
            try await api?.deleteUser(id: id)
            await loadUsers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scanLibrary() async {
        isScanning = true
        scanMessage = nil
        do {
            let response = try await api?.scanLibrary()
            scanMessage = response?.message ?? "Scan complete"
        } catch {
            scanMessage = "Scan failed: \(error.localizedDescription)"
        }
        isScanning = false
    }

    private func forceRescan() async {
        isScanning = true
        scanMessage = nil
        do {
            let response = try await api?.forceRescan()
            scanMessage = response?.message ?? "Rescan complete"
        } catch {
            scanMessage = "Rescan failed: \(error.localizedDescription)"
        }
        isScanning = false
    }
}

struct AdminUserRow: View {
    let user: AdminUser
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(user.username)
                        .foregroundColor(.sapphoTextHigh)

                    if user.isAdminUser {
                        Text("Admin")
                            .font(.sapphoSmall)
                            .foregroundColor(.sapphoPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.sapphoPrimary.opacity(0.2))
                            .cornerRadius(8)
                    }

                    if user.isAccountDisabled {
                        Text("Disabled")
                            .font(.sapphoSmall)
                            .foregroundColor(.sapphoError)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.sapphoError.opacity(0.2))
                            .cornerRadius(8)
                    }
                }

                if let email = user.email {
                    Text(email)
                        .font(.sapphoSmall)
                        .foregroundColor(.sapphoTextMuted)
                }
            }

            Spacer()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.sapphoError)
            }
            .buttonStyle(.plain)
        }
    }
}

struct CreateUserSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var isAdmin = false
    let onCreate: (String, String, Bool) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)

                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                }

                Section {
                    Toggle("Administrator", isOn: $isAdmin)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.sapphoBackground)
            .navigationTitle("New User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.sapphoSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(username, password, isAdmin)
                    }
                    .disabled(username.isEmpty || password.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Profile Edit View
struct ProfileEditView: View {
    @Environment(\.sapphoAPI) private var api
    @Environment(AuthRepository.self) private var authRepository
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var email = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showPasswordChange = false
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var avatarKey = UUID() // For refreshing avatar image

    var body: some View {
        Form {
            // Avatar Section
            Section {
                HStack {
                    Spacer()
                    Button {
                        showImagePicker = true
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            if let image = selectedImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            } else {
                                AsyncImage(url: api?.avatarURL()) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Circle()
                                        .fill(Color.sapphoSurface)
                                        .overlay(
                                            Text(String(displayName.prefix(1).uppercased()))
                                                .font(.sapphoTitle)
                                                .foregroundColor(.sapphoTextMuted)
                                        )
                                }
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                                .id(avatarKey)
                            }

                            Circle()
                                .fill(Color.sapphoPrimary)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)

            // Profile Info Section
            Section("Profile Information") {
                TextField("Display Name", text: $displayName)
                    .textContentType(.name)

                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
            }

            // Password Section
            Section("Security") {
                Button {
                    showPasswordChange = true
                } label: {
                    HStack {
                        Text("Change Password")
                            .foregroundColor(.sapphoTextHigh)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(.sapphoTextMuted)
                    }
                }
            }

            // Error Message
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.sapphoError)
                        .font(.sapphoSmall)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.sapphoBackground)
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await saveProfile() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isSaving)
            }
        }
        .sheet(isPresented: $showPasswordChange) {
            PasswordChangeSheet()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .onChange(of: selectedImage) { _, newImage in
            if newImage != nil {
                Task { await uploadAvatar() }
            }
        }
        .onAppear {
            if let user = authRepository.currentUser {
                displayName = user.displayName ?? user.username ?? ""
                email = user.email ?? ""
            }
        }
    }

    private func saveProfile() async {
        isSaving = true
        errorMessage = nil

        do {
            let updatedUser = try await api?.updateProfile(
                displayName: displayName.isEmpty ? nil : displayName,
                email: email.isEmpty ? nil : email
            )
            if let user = updatedUser {
                authRepository.updateUser(user)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    private func uploadAvatar() async {
        guard let image = selectedImage,
              let imageData = image.jpegData(compressionQuality: 0.8) else { return }

        isSaving = true
        errorMessage = nil

        do {
            try await api?.uploadAvatar(imageData: imageData)
            avatarKey = UUID() // Refresh avatar
        } catch {
            errorMessage = "Failed to upload avatar: \(error.localizedDescription)"
        }

        isSaving = false
    }
}

// MARK: - Password Change Sheet
struct PasswordChangeSheet: View {
    @Environment(\.sapphoAPI) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var passwordsMatch: Bool {
        !newPassword.isEmpty && newPassword == confirmPassword
    }

    private var isValid: Bool {
        !currentPassword.isEmpty && passwordsMatch && newPassword.count >= 6
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Current Password", text: $currentPassword)
                        .textContentType(.password)
                }

                Section {
                    SecureField("New Password", text: $newPassword)
                        .textContentType(.newPassword)

                    SecureField("Confirm New Password", text: $confirmPassword)
                        .textContentType(.newPassword)

                    if !newPassword.isEmpty && !confirmPassword.isEmpty && !passwordsMatch {
                        Text("Passwords don't match")
                            .font(.sapphoSmall)
                            .foregroundColor(.sapphoError)
                    }

                    if !newPassword.isEmpty && newPassword.count < 6 {
                        Text("Password must be at least 6 characters")
                            .font(.sapphoSmall)
                            .foregroundColor(.sapphoError)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.sapphoError)
                            .font(.sapphoSmall)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.sapphoBackground)
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.sapphoSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await changePassword() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func changePassword() async {
        isSaving = true
        errorMessage = nil

        do {
            try await api?.updatePassword(currentPassword: currentPassword, newPassword: newPassword)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.editedImage] as? UIImage {
                parent.image = image
            } else if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    ProfileView()
        .environment(AuthRepository())
        .environment(AudioPlayerService())
}
