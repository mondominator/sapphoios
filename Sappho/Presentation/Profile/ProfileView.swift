import SwiftUI

struct ProfileView: View {
    @Environment(AuthRepository.self) private var authRepository
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(\.sapphoAPI) private var api

    @State private var stats: UserStats?
    @State private var isLoading = true
    @State private var serverVersion: String?
    @State private var showLogoutConfirmation = false

    // Inline editing
    @State private var displayName = ""
    @State private var email = ""
    @State private var isSaving = false
    @State private var saveMessage: String?

    // Avatar
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var avatarKey = UUID()
    @State private var avatarLoader = ImageLoader()

    // Password
    @State private var showPasswordSection = false
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordError: String?
    @State private var isChangingPassword = false

    private var avatarInitial: String {
        let name = authRepository.currentUser?.displayName
            ?? authRepository.currentUser?.username
            ?? authRepository.currentLoginUser?.username
            ?? "?"
        return String(name.prefix(1)).uppercased()
    }

    private var displayUser: User? {
        authRepository.currentUser
    }

    private var currentName: String {
        authRepository.currentUser?.displayName
            ?? authRepository.currentUser?.username
            ?? authRepository.currentLoginUser?.username
            ?? "User"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // SECTION 1: AVATAR
                    Spacer().frame(height: 24)
                    avatarSection(user: displayUser)

                    // SECTION 2: STATS
                    if let stats = stats {
                        statsSection(stats: stats)
                    }

                    // SECTION 3: RECENT
                    if let stats = stats, !stats.recentActivity.isEmpty {
                        recentSection(activity: stats.recentActivity)
                    }

                    // SECTION 4: ACCOUNT
                    accountSection()

                    // SECTION 5: SECURITY
                    securitySection()

                    // SECTION 6: PLAYER
                    playerSection()

                    // SECTION 7: ABOUT
                    aboutSection()

                    Spacer().frame(height: 100)
                }
            }
            .background(Color.sapphoBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("Logout", isPresented: $showLogoutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Logout", role: .destructive) {
                    audioPlayer.showFullPlayer = false
                    audioPlayer.stop()
                    authRepository.clear()
                }
            } message: {
                Text("Are you sure you want to logout?")
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $selectedImage)
            }
            .onChange(of: selectedImage) { _, newImage in
                if newImage != nil {
                    Task { await uploadAvatar() }
                }
            }
            .task {
                syncUserFields()
                avatarLoader.load(url: api?.avatarURL(), headers: api?.authHeaders ?? [:])
                await loadData()
            }
        }
    }

    // MARK: - Avatar Section

    @ViewBuilder
    private func avatarSection(user: User?) -> some View {
        // Avatar circle (tappable)
        Button {
            showImagePicker = true
        } label: {
            ZStack(alignment: .bottom) {
                Circle()
                    .fill(avatarGradient(for: currentName))
                    .frame(width: 100, height: 100)
                    .overlay {
                        Group {
                            if let image = selectedImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else if user?.avatar != nil, let img = avatarLoader.image {
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Text(avatarInitial)
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.sapphoTextHigh)
                            }
                        }
                    }
                    .clipShape(Circle())

                // "Edit" overlay at bottom
                VStack {
                    Spacer()
                    Text("Edit")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.sapphoTextHigh)
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .background(Color.sapphoBackground.opacity(0.7))
                }
                .frame(width: 100, height: 100)
                .clipShape(Circle())
            }
        }
        .buttonStyle(.plain)

        // Remove photo link
        if user?.avatar != nil {
            Button("Remove photo") {
                Task { await deleteAvatar() }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.sapphoTextMuted)
            .padding(.top, 4)
        } else {
            Spacer().frame(height: 8)
        }

        // Display name
        Text(currentName)
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(.sapphoTextHigh)
            .padding(.top, 8)

        // Member since
        Text(memberSinceText(user: user))
            .font(.system(size: 13))
            .foregroundColor(.sapphoTextMuted)
            .padding(.top, 2)

        Spacer().frame(height: 24)
    }

    // MARK: - Stats Section

    @ViewBuilder
    private func statsSection(stats: UserStats) -> some View {
        let (hours, minutes) = formatListenTime(stats.totalListenTime)

        HStack(spacing: 0) {
            // Listen Time
            VStack(spacing: 2) {
                HStack(alignment: .bottom, spacing: 0) {
                    Text("\(hours)")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.sapphoTextHigh)
                    Text("h")
                        .font(.system(size: 13))
                        .foregroundColor(.sapphoTextMuted)
                        .padding(.leading, 1)
                    Spacer().frame(width: 4)
                    Text("\(minutes)")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.sapphoTextHigh)
                    Text("m")
                        .font(.system(size: 13))
                        .foregroundColor(.sapphoTextMuted)
                        .padding(.leading, 1)
                }
                Text("listened")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.sapphoTextMuted)
            }
            .frame(maxWidth: .infinity)

            // Divider
            Rectangle()
                .fill(Color.sapphoBorder)
                .frame(width: 1, height: 40)

            // Finished
            VStack(spacing: 2) {
                Text("\(stats.booksCompleted)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.sapphoTextHigh)
                Text("finished")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.sapphoTextMuted)
            }
            .frame(maxWidth: .infinity)

            // Divider
            Rectangle()
                .fill(Color.sapphoBorder)
                .frame(width: 1, height: 40)

            // In Progress
            VStack(spacing: 2) {
                Text("\(stats.currentlyListening)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.sapphoTextHigh)
                Text("in progress")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.sapphoTextMuted)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)

        // Full-width divider
        Rectangle()
            .fill(Color.sapphoBorder)
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    // MARK: - Recent Section

    @ViewBuilder
    private func recentSection(activity: [RecentActivityItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 24)

            sectionTitle("Recent")
                .padding(.horizontal, 16)

            Spacer().frame(height: 12)

            HStack(spacing: 12) {
                ForEach(Array(activity.prefix(4))) { book in
                    recentBookCover(book: book)
                }
                // Fill remaining empty slots
                if activity.count < 4 {
                    ForEach(0..<(4 - min(activity.count, 4)), id: \.self) { _ in
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func recentBookCover(book: RecentActivityItem) -> some View {
        ZStack(alignment: .bottom) {
            CoverImage(audiobookId: book.id, cornerRadius: 8, contentMode: .fill)
                .aspectRatio(1, contentMode: .fit)

            // Progress bar
            if let duration = book.duration, duration > 0, book.completed != 1 {
                let progress = min(1.0, Double(book.position) / Double(duration))
                if progress > 0 {
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            Rectangle()
                                .fill(Color.sapphoPrimary)
                                .frame(width: geo.size.width * progress, height: 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.sapphoSurfaceSlate)
        )
    }

    // MARK: - Account Section

    @ViewBuilder
    private func accountSection() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 32)

            sectionTitle("Account")
                .padding(.horizontal, 16)

            Spacer().frame(height: 12)

            // Display Name field
            outlinedTextField("Display Name", text: $displayName)
                .textContentType(.name)
                .padding(.horizontal, 16)

            Spacer().frame(height: 12)

            // Email field
            outlinedTextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 16)

            Spacer().frame(height: 16)

            // Save button
            Button {
                Task { await saveProfile() }
            } label: {
                Text(isSaving ? "Saving..." : "Save Changes")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.sapphoPrimary)
                    .cornerRadius(8)
            }
            .disabled(isSaving)
            .padding(.horizontal, 16)

            // Save message
            if let message = saveMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(message.hasPrefix("Error") ? .sapphoError : .sapphoSuccess)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Security Section

    @ViewBuilder
    private func securitySection() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 32)

            sectionTitle("Security")
                .padding(.horizontal, 16)

            Spacer().frame(height: 12)

            if !showPasswordSection {
                Button {
                    withAnimation { showPasswordSection = true }
                } label: {
                    Text("Change Password")
                        .font(.system(size: 14))
                        .foregroundColor(.sapphoTextHigh)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.sapphoBorder, lineWidth: 1)
                        )
                }
                .padding(.horizontal, 16)
            }

            if showPasswordSection {
                VStack(spacing: 12) {
                    outlinedSecureField("Current Password", text: $currentPassword)

                    outlinedSecureField("New Password", text: $newPassword)

                    VStack(alignment: .leading, spacing: 4) {
                        outlinedSecureField("Confirm Password", text: $confirmPassword)

                        if let error = passwordError {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundColor(.sapphoError)
                        }
                    }

                    // Button row
                    HStack(spacing: 12) {
                        // Cancel
                        Button {
                            withAnimation {
                                showPasswordSection = false
                                currentPassword = ""
                                newPassword = ""
                                confirmPassword = ""
                                passwordError = nil
                            }
                        } label: {
                            Text("Cancel")
                                .font(.system(size: 14))
                                .foregroundColor(.sapphoTextMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.sapphoBorder, lineWidth: 1)
                                )
                        }

                        // Change Password
                        Button {
                            Task { await changePassword() }
                        } label: {
                            Text(isChangingPassword ? "Changing..." : "Change Password")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.sapphoPrimary)
                                .cornerRadius(8)
                        }
                        .disabled(isChangingPassword)
                    }
                }
                .padding(.horizontal, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Player Section

    @ViewBuilder
    private func playerSection() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 32)

            sectionTitle("Player")
                .padding(.horizontal, 16)

            Spacer().frame(height: 12)

            NavigationLink {
                SettingsView()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                    Text("Playback Settings")
                        .font(.system(size: 14))
                }
                .foregroundColor(.sapphoTextHigh)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.sapphoBorder, lineWidth: 1)
                )
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - About Section

    @ViewBuilder
    private func aboutSection() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 32)

            sectionTitle("About")
                .padding(.horizontal, 16)

            Spacer().frame(height: 12)

            // Version info card
            VStack(spacing: 0) {
                HStack {
                    Text("App Version")
                        .font(.system(size: 14))
                        .foregroundColor(.sapphoTextMuted)
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                        .font(.system(size: 14))
                        .foregroundColor(.sapphoTextHigh)
                }

                if let version = serverVersion {
                    Spacer().frame(height: 8)
                    HStack {
                        Text("Server Version")
                            .font(.system(size: 14))
                            .foregroundColor(.sapphoTextMuted)
                        Spacer()
                        Text(version)
                            .font(.system(size: 14))
                            .foregroundColor(.sapphoTextHigh)
                    }
                }
            }
            .padding(16)
            .background(Color.sapphoSurfaceSlate)
            .cornerRadius(8)
            .padding(.horizontal, 16)

            Spacer().frame(height: 16)

            // Logout button
            Button {
                showLogoutConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 16))
                    Text("Logout")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.sapphoError)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.sapphoError.opacity(0.15))
                .cornerRadius(8)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Helper Views

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.sapphoTextMuted)
            .tracking(0.5)
    }

    private func outlinedTextField(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .font(.system(size: 14))
            .foregroundStyle(Color.sapphoTextHigh)
            .padding(12)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.sapphoBorder, lineWidth: 1)
            )
    }

    private func outlinedSecureField(_ label: String, text: Binding<String>) -> some View {
        SecureField(label, text: text)
            .font(.system(size: 14))
            .foregroundStyle(Color.sapphoTextHigh)
            .padding(12)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.sapphoBorder, lineWidth: 1)
            )
    }

    // MARK: - Computed Properties

    private func avatarGradient(for name: String) -> LinearGradient {
        let hash = abs(name.hashValue)
        let hue = Double(hash % 360) / 360.0
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.6, brightness: 0.4),
                Color(hue: hue, saturation: 0.5, brightness: 0.3)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func memberSinceText(user: User?) -> String {
        let prefix = (user?.isAdminUser ?? false) ? "Admin" : "Member"
        guard let createdAt = user?.createdAt else { return prefix }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: createdAt) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MMM yyyy"
            return "\(prefix) since \(displayFormatter.string(from: date))"
        }

        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: createdAt) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MMM yyyy"
            return "\(prefix) since \(displayFormatter.string(from: date))"
        }

        return prefix
    }

    private func formatListenTime(_ totalSeconds: Int) -> (hours: Int, minutes: Int) {
        let totalMinutes = totalSeconds / 60
        return (totalMinutes / 60, totalMinutes % 60)
    }

    // MARK: - Data Operations

    private func syncUserFields() {
        if let user = authRepository.currentUser {
            displayName = user.displayName ?? user.username ?? ""
            email = user.email ?? ""
        } else if let loginUser = authRepository.currentLoginUser {
            displayName = loginUser.username
            email = ""
        }
    }

    private func loadData() async {
        // Load user profile if not already set
        if authRepository.currentUser == nil {
            do {
                let user = try await api?.getProfile()
                if let user = user {
                    authRepository.updateUser(user)
                }
            } catch {
                print("Failed to load profile: \(error)")
            }
        }

        do {
            stats = try await api?.getProfileStats()
        } catch {
            print("Failed to load stats: \(error)")
        }

        do {
            let health = try await api?.getHealth()
            serverVersion = health?.version
        } catch {
            print("Failed to load server version: \(error)")
        }
        isLoading = false
    }

    private func saveProfile() async {
        isSaving = true
        saveMessage = nil

        do {
            let updatedUser = try await api?.updateProfile(
                displayName: displayName.isEmpty ? nil : displayName,
                email: email.isEmpty ? nil : email
            )
            if let user = updatedUser {
                authRepository.updateUser(user)
            }
            saveMessage = "Profile updated"
            Task {
                try? await Task.sleep(for: .seconds(3))
                saveMessage = nil
            }
        } catch {
            saveMessage = "Error: \(error.localizedDescription)"
        }

        isSaving = false
    }

    private func uploadAvatar() async {
        guard let image = selectedImage,
              let imageData = image.jpegData(compressionQuality: 0.8) else { return }

        isSaving = true

        do {
            try await api?.uploadAvatar(imageData: imageData)
            avatarLoader = ImageLoader()
            avatarLoader.load(url: api?.avatarURL(), headers: api?.authHeaders ?? [:])
            if let updatedUser = try? await api?.getProfile() {
                authRepository.updateUser(updatedUser)
            }
        } catch {
            saveMessage = "Error: Failed to upload avatar"
        }

        isSaving = false
    }

    private func deleteAvatar() async {
        do {
            try await api?.deleteAvatar()
            selectedImage = nil
            avatarLoader = ImageLoader()
            if let updatedUser = try? await api?.getProfile() {
                authRepository.updateUser(updatedUser)
            }
        } catch {
            saveMessage = "Error: Failed to remove avatar"
        }
    }

    private func changePassword() async {
        passwordError = nil

        guard newPassword.count >= 6 else {
            passwordError = "Password must be at least 6 characters"
            return
        }

        guard newPassword == confirmPassword else {
            passwordError = "Passwords don't match"
            return
        }

        isChangingPassword = true

        do {
            try await api?.updatePassword(currentPassword: currentPassword, newPassword: newPassword)
            withAnimation {
                showPasswordSection = false
                currentPassword = ""
                newPassword = ""
                confirmPassword = ""
            }
            saveMessage = "Password changed"
            Task {
                try? await Task.sleep(for: .seconds(3))
                saveMessage = nil
            }
        } catch {
            passwordError = error.localizedDescription
        }

        isChangingPassword = false
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = 30
    @AppStorage("skipBackwardSeconds") private var skipBackwardSeconds = 15
    @AppStorage("rewindOnResume") private var rewindOnResume = 0

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

                Picker("Rewind on Resume", selection: $rewindOnResume) {
                    Text("Off").tag(0)
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                }

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
        .contentMargins(.bottom, 100)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

struct DownloadsView: View {
    @State private var downloadedBooks: [Audiobook] = []

    private var downloadManager: DownloadManager { DownloadManager.shared }

    var body: some View {
        Group {
            if downloadedBooks.isEmpty {
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            loadDownloads()
        }
    }

    private func loadDownloads() {
        downloadedBooks = downloadManager.downloadedAudiobooks()
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
        .navigationBarTitleDisplayMode(.inline)
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
