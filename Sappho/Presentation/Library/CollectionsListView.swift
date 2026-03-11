import SwiftUI

struct CollectionsListView: View {
    @Environment(\.sapphoAPI) private var api
    @State private var collections: [Collection] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var newCollectionName = ""
    @State private var newCollectionDescription = ""
    @State private var newCollectionIsPublic = false

    var body: some View {
        Group {
            if isLoading {
                LoadingView()
            } else if let error = errorMessage {
                ErrorView(message: error) {
                    Task { await loadData() }
                }
            } else if collections.isEmpty {
                VStack(spacing: 16) {
                    EmptyStateView(
                        icon: "folder",
                        title: "No Collections",
                        message: "Create a collection to organize your audiobooks."
                    )
                    Button("Create Collection") {
                        showCreateSheet = true
                    }
                    .buttonStyle(SapphoPrimaryButtonStyle())
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Create new collection button
                        Button {
                            showCreateSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.sapphoPrimary)
                                Text("Create New Collection")
                                    .font(.sapphoSubheadline)
                                    .foregroundColor(.sapphoPrimary)
                                Spacer()
                            }
                            .padding(16)
                            .background(Color.sapphoSurface)
                            .cornerRadius(12)
                        }

                        ForEach(collections) { collection in
                            NavigationLink {
                                CollectionDetailView(collection: collection)
                            } label: {
                                CollectionCard(collection: collection)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 100)
                }
            }
        }
        .background(Color.sapphoBackground)
        .sheet(isPresented: $showCreateSheet) {
            CreateCollectionSheet(
                name: $newCollectionName,
                description: $newCollectionDescription,
                isPublic: $newCollectionIsPublic,
                onCreate: {
                    Task {
                        await createCollection()
                    }
                },
                onCancel: {
                    resetCreateForm()
                    showCreateSheet = false
                }
            )
        }
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            collections = try await api?.getCollections() ?? []
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func createCollection() async {
        guard !newCollectionName.isEmpty else { return }

        do {
            let _ = try await api?.createCollection(
                name: newCollectionName,
                description: newCollectionDescription.isEmpty ? nil : newCollectionDescription,
                isPublic: newCollectionIsPublic
            )
            resetCreateForm()
            showCreateSheet = false
            await loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetCreateForm() {
        newCollectionName = ""
        newCollectionDescription = ""
        newCollectionIsPublic = false
    }
}

struct CollectionCard: View {
    @Environment(\.sapphoAPI) private var api
    let collection: Collection

    var body: some View {
        HStack(spacing: 16) {
            // Cover stack or placeholder
            ZStack {
                if let bookIds = collection.bookIds, !bookIds.isEmpty {
                    ForEach(Array(bookIds.prefix(3).reversed().enumerated()), id: \.offset) { index, bookId in
                        let offset = CGFloat(2 - index) * 6
                        CoverImage(audiobookId: bookId)
                            .frame(width: 50, height: 70)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.sapphoSurface, lineWidth: 1)
                            )
                            .offset(x: offset, y: offset)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.sapphoSurfaceElevated)
                        .frame(width: 50, height: 70)
                        .overlay(
                            Image(systemName: "folder.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.sapphoTextMuted)
                        )
                }
            }
            .frame(width: 70, height: 90)

            // Collection info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(collection.name)
                        .font(.sapphoSubheadline)
                        .foregroundColor(.sapphoTextHigh)
                        .lineLimit(2)

                    if collection.isPublic == 1 {
                        Image(systemName: "globe")
                            .font(.system(size: 12))
                            .foregroundColor(.sapphoPrimary)
                    }
                }

                if let description = collection.description, !description.isEmpty {
                    Text(description)
                        .font(.sapphoSmall)
                        .foregroundColor(.sapphoTextMuted)
                        .lineLimit(2)
                }

                Spacer().frame(height: 4)

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.sapphoPrimary)
                        Text("\(collection.bookCount ?? 0)")
                            .font(.sapphoSmall)
                            .foregroundColor(.sapphoTextMuted)
                    }

                    if let creator = collection.creatorUsername, collection.isOwner != 1 {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.sapphoTextMuted)
                            Text(creator)
                                .font(.sapphoSmall)
                                .foregroundColor(.sapphoTextMuted)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.sapphoTextMuted)
        }
        .padding(12)
        .background(Color.sapphoSurface)
        .cornerRadius(12)
    }
}

struct CreateCollectionSheet: View {
    @Binding var name: String
    @Binding var description: String
    @Binding var isPublic: Bool
    let onCreate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Collection Name", text: $name)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Toggle("Public Collection", isOn: $isPublic)
                } footer: {
                    Text("Public collections can be viewed and added to by other users.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.sapphoBackground)
            .navigationTitle("New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.sapphoSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: onCreate)
                        .disabled(name.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct CollectionDetailView: View {
    @Environment(\.sapphoAPI) private var api
    @Environment(\.dismiss) private var dismiss
    let collection: Collection

    @State private var collectionDetail: CollectionDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showDeleteAlert = false

    var body: some View {
        Group {
            if isLoading {
                LoadingView()
            } else if let error = errorMessage {
                ErrorView(message: error) {
                    Task { await loadData() }
                }
            } else if let detail = collectionDetail {
                if detail.books.isEmpty {
                    EmptyStateView(
                        icon: "folder",
                        title: "Empty Collection",
                        message: "Add audiobooks to this collection from the book detail page."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(detail.books) { audiobook in
                                NavigationLink {
                                    AudiobookDetailView(audiobook: audiobook)
                                } label: {
                                    BookListItem(audiobook: audiobook)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 100)
                    }
                }
            }
        }
        .background(Color.sapphoBackground)
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if collection.isOwner == 1 {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("Delete Collection", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Delete Collection?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await deleteCollection()
                }
            }
        } message: {
            Text("This action cannot be undone. The audiobooks will not be deleted.")
        }
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            collectionDetail = try await api?.getCollection(id: collection.id)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func deleteCollection() async {
        do {
            try await api?.deleteCollection(id: collection.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        CollectionsListView()
    }
    .environment(AuthRepository())
}
