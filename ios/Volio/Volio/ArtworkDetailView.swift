import SwiftUI

struct ArtworkDetailView: View {
    @Environment(VolioSession.self) private var session
    @State var artwork: Artwork
    @State private var showingEditor = false
    @State private var isAnalyzing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AsyncImage(url: URL(string: artwork.displayAbsoluteURL ?? artwork.originalAbsoluteURL ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        ContentUnavailableView("Image unavailable", systemImage: "photo")
                    default:
                        ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 8) {
                    Text(artwork.title?.isEmpty == false ? artwork.title! : "Untitled artwork")
                        .font(.title2.bold())
                    Text([artwork.childName, artwork.childAgeLabel ?? artwork.createdAroundLabel, artwork.workType?.capitalized, artwork.aiStatus].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    if let age = artwork.childAgeLabel {
                        DetailChip(icon: "figure.child", title: age)
                    }
                    if let created = artwork.createdAroundLabel {
                        DetailChip(icon: "calendar", title: created)
                    }
                }

                if let description = artwork.description, !description.isEmpty {
                    DetailBlock(title: "Brief", text: description)
                }
                if let longDescription = artwork.longDescription, !longDescription.isEmpty {
                    DetailBlock(title: "Description", text: longDescription)
                }
                if let quote = artwork.childQuote, !quote.isEmpty {
                    DetailBlock(title: "Child Quote", text: quote)
                }
                if let note = artwork.parentNote, !note.isEmpty {
                    DetailBlock(title: "Parent Note", text: note)
                }
                if let tags = artwork.tags, !tags.isEmpty {
                    FlowTags(tags: tags)
                }
            }
            .padding(16)
        }
        .navigationTitle("Artwork")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await analyze() }
                } label: {
                    if isAnalyzing {
                        ProgressView()
                    } else {
                        Image(systemName: "sparkles")
                    }
                }
                Button("Edit") {
                    showingEditor = true
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            ArtworkEditorView(artwork: artwork) { updated in
                artwork = updated
                Task { await session.refresh() }
            }
        }
    }

    private func analyze() async {
        guard let client = session.client else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            try await client.analyzeArtwork(id: artwork.id)
            await session.refresh()
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }
}

struct DetailBlock: View {
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(text)
                .font(.body)
        }
    }
}

struct DetailChip: View {
    var icon: String
    var title: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.blue.opacity(0.1), in: Capsule())
            .foregroundStyle(.blue)
    }
}

struct FlowTags: View {
    var tags: [ArtworkTag]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(tags) { tag in
                    Text(tag.name)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.blue.opacity(0.1), in: Capsule())
                        .foregroundStyle(.blue)
                }
            }
        }
    }
}

struct ArtworkEditorView: View {
    @Environment(VolioSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var artworkDate: String
    @State private var dateNote: String
    @State private var childQuote: String
    @State private var parentNote: String
    @State private var isFavorite: Bool
    @State private var isRepresentative: Bool
    @State private var isSaving = false
    var artwork: Artwork
    var onSave: (Artwork) -> Void

    init(artwork: Artwork, onSave: @escaping (Artwork) -> Void) {
        self.artwork = artwork
        self.onSave = onSave
        _title = State(initialValue: artwork.title ?? "")
        _artworkDate = State(initialValue: artwork.artworkDate ?? "")
        _dateNote = State(initialValue: artwork.dateNote ?? "")
        _childQuote = State(initialValue: artwork.childQuote ?? "")
        _parentNote = State(initialValue: artwork.parentNote ?? "")
        _isFavorite = State(initialValue: artwork.isFavorite?.boolValue ?? false)
        _isRepresentative = State(initialValue: artwork.isRepresentative?.boolValue ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Artwork") {
                    TextField("Title", text: $title)
                    TextField("Created around", text: $artworkDate)
                    TextField("Date note", text: $dateNote)
                }
                Section("Story") {
                    TextField("Child quote", text: $childQuote, axis: .vertical)
                    TextField("Parent note", text: $parentNote, axis: .vertical)
                }
                Section("Flags") {
                    Toggle("Favorite", isOn: $isFavorite)
                    Toggle("Representative", isOn: $isRepresentative)
                }
            }
            .navigationTitle("Edit Artwork")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        guard let client = session.client else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await client.updateArtwork(id: artwork.id, patch: [
                "title": .string(title),
                "artwork_date": .string(artworkDate),
                "date_note": .string(dateNote),
                "child_quote": .string(childQuote),
                "parent_note": .string(parentNote),
                "is_favorite": .bool(isFavorite),
                "is_representative": .bool(isRepresentative),
            ])
            onSave(updated)
            dismiss()
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }
}
