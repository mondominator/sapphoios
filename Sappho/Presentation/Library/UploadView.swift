import SwiftUI
import UniformTypeIdentifiers

struct UploadView: View {
    @Environment(\.sapphoAPI) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFiles: [URL] = []
    @State private var title = ""
    @State private var author = ""
    @State private var narrator = ""
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var uploadResult: String?
    @State private var uploadError: String?
    @State private var showFilePicker = false

    private let supportedTypes: [UTType] = [.audio, .mpeg4Audio, .mp3]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Supported formats
                    Text("Supported: MP3, M4A, M4B, FLAC, OGG, WAV")
                        .font(.sapphoSmall)
                        .foregroundColor(.sapphoTextMuted)

                    // File picker button
                    Button {
                        showFilePicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .font(.sapphoSubheadline)
                            Text("Select Files")
                                .font(.sapphoSubheadline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.sapphoPrimary)
                        .cornerRadius(8)
                    }

                    // Selected files
                    if !selectedFiles.isEmpty {
                        HStack {
                            Text("\(selectedFiles.count) file(s) selected")
                                .font(.sapphoBody)
                                .foregroundColor(.sapphoSuccess)
                            Spacer()
                            Button("Clear") {
                                selectedFiles = []
                            }
                            .font(.sapphoSmall)
                            .foregroundColor(.sapphoError)
                        }

                        ForEach(selectedFiles.prefix(5), id: \.absoluteString) { url in
                            HStack(spacing: 8) {
                                Image(systemName: "music.note")
                                    .font(.sapphoDetail)
                                    .foregroundColor(.sapphoTextMuted)
                                Text(url.lastPathComponent)
                                    .font(.sapphoSmall)
                                    .foregroundColor(.sapphoTextHigh)
                                    .lineLimit(1)
                            }
                        }

                        if selectedFiles.count > 5 {
                            Text("...and \(selectedFiles.count - 5) more")
                                .font(.sapphoSmall)
                                .foregroundColor(.sapphoTextMuted)
                        }

                        // Metadata fields
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Optional metadata (leave blank to auto-detect)")
                                .font(.sapphoSmall)
                                .foregroundColor(.sapphoTextMuted)
                        }

                        VStack(spacing: 12) {
                            UploadTextField(label: "Title", text: $title)
                            UploadTextField(label: "Author", text: $author)
                            UploadTextField(label: "Narrator", text: $narrator)
                        }
                    }

                    // Upload progress
                    if isUploading {
                        VStack(spacing: 8) {
                            ProgressView(value: uploadProgress)
                                .tint(.sapphoPrimary)
                            Text("Uploading... \(Int(uploadProgress * 100))%")
                                .font(.sapphoSmall)
                                .foregroundColor(.sapphoTextMuted)
                        }
                    }

                    // Result message
                    if let result = uploadResult {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.sapphoSuccess)
                            Text(result)
                                .font(.sapphoBody)
                                .foregroundColor(.sapphoSuccess)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.sapphoSuccess.opacity(0.1))
                        .cornerRadius(8)
                    }

                    if let error = uploadError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.sapphoError)
                            Text(error)
                                .font(.sapphoBody)
                                .foregroundColor(.sapphoError)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.sapphoError.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding(16)
            }
            .background(Color.sapphoBackground)
            .navigationTitle("Upload Audiobooks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.sapphoSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload") {
                        Task { await uploadFiles() }
                    }
                    .disabled(selectedFiles.isEmpty || isUploading)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: supportedTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    selectedFiles = urls
                case .failure(let error):
                    uploadError = error.localizedDescription
                }
            }
        }
    }

    private func uploadFiles() async {
        isUploading = true
        uploadError = nil
        uploadResult = nil

        let totalFiles = selectedFiles.count
        var successCount = 0

        for (index, fileURL) in selectedFiles.enumerated() {
            guard fileURL.startAccessingSecurityScopedResource() else {
                uploadError = "Cannot access file: \(fileURL.lastPathComponent)"
                continue
            }
            defer { fileURL.stopAccessingSecurityScopedResource() }

            do {
                let fileData = try Data(contentsOf: fileURL)
                let mimeType = mimeTypeForPath(fileURL.pathExtension)

                _ = try await api?.uploadAudiobook(
                    fileData: fileData,
                    fileName: fileURL.lastPathComponent,
                    mimeType: mimeType,
                    title: title.isEmpty ? nil : title,
                    author: author.isEmpty ? nil : author,
                    narrator: narrator.isEmpty ? nil : narrator,
                    onProgress: { progress in
                        let fileProgress = (Double(index) + progress) / Double(totalFiles)
                        Task { @MainActor in uploadProgress = fileProgress }
                    }
                )
                successCount += 1
            } catch {
                uploadError = "Failed to upload \(fileURL.lastPathComponent): \(error.localizedDescription)"
            }
        }

        uploadProgress = 1.0
        isUploading = false

        if successCount > 0 {
            uploadResult = "Successfully uploaded \(successCount) file(s)"
        }
    }

    private func mimeTypeForPath(_ ext: String) -> String {
        switch ext.lowercased() {
        case "mp3": return "audio/mpeg"
        case "m4a", "m4b": return "audio/mp4"
        case "flac": return "audio/flac"
        case "ogg": return "audio/ogg"
        case "wav": return "audio/wav"
        default: return "audio/mpeg"
        }
    }
}

// MARK: - Upload Text Field
struct UploadTextField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.sapphoSmall)
                .foregroundColor(.sapphoTextMuted)
            TextField("", text: $text)
                .font(.sapphoBody)
                .foregroundColor(.sapphoTextHigh)
                .padding(10)
                .background(Color.sapphoSurface)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.sapphoTextMuted.opacity(0.3), lineWidth: 1)
                )
        }
    }
}
