import SwiftUI

struct ArtworkDetailView: View {
    @Environment(VolioSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State var work: LocalWork
    @State private var showEditor = false
    @State private var showShareCard = false
    @State private var quoteText = ""

    private let accentColor = VolioTheme.accent
    private var artwork: Artwork {
        work.detailArtwork(profileName: session.profile.name)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Image
                if let path = work.originalPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(displayTitle)
                            .font(.title2.bold())
                            .foregroundStyle(VolioTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        aiPill
                    }

                    HStack(spacing: 6) {
                        Text(artwork.createdAroundLabel ?? work.createdAroundLabel)
                        Text("·")
                        Text((artwork.workType ?? work.workType).capitalized)
                        if let age = artwork.childAgeMonths ?? work.ageAtCreationMonths ?? work.createdAroundAgeMonths {
                            Text("·")
                            Text(artwork.childAgeLabel ?? ageLabel(age))
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VolioTheme.mutedInk)
                }
                .padding(.horizontal, 16)

                // Actions
                HStack(spacing: 14) {
                    Button {
                        showShareCard = true
                    } label: {
                        Label("Share Card", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
                    .controlSize(.large)
                }
                .padding(.horizontal, 16)

                processingCard

                detailSections
            }
            .padding(.bottom, 24)
        }
        .background(VolioTheme.paper)
        .navigationTitle("Artwork")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEditor = true
                } label: {
                    Text("Edit")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showEditor) {
            ArtworkEditorView(
                work: work,
                onSave: { updated in
                work = updated
                },
                onDelete: {
                    session.deleteWork(work)
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $showShareCard) {
            ShareCardView(work: work)
        }
        .onAppear {
            session.isShowingDetail = true
        }
        .task(id: work.remoteArtworkId) {
            await session.refreshWorkFromMac(work)
        }
        .onDisappear {
            session.isShowingDetail = false
        }
    }

    private var aiPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(processingColor)
                .frame(width: 7, height: 7)
            Text("AI")
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(processingColor)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(processingColor.opacity(0.12), in: Capsule())
    }

    private var detailSections: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let brief = clean(artwork.description) {
                DetailSection("Brief") {
                    Text(brief)
                        .font(.body)
                        .foregroundStyle(VolioTheme.ink)
                }
            }

            if let description = clean(artwork.longDescription), description != clean(artwork.description) {
                DetailSection("Description") {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(VolioTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            DetailSection("Tags") {
                let tags = detailTags
                if tags.isEmpty {
                    Text("No tags")
                        .font(.subheadline)
                        .foregroundStyle(VolioTheme.mutedInk)
                } else {
                    FlowLayout(spacing: 8, rowSpacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(VolioTheme.blue.opacity(0.10), in: Capsule())
                                .foregroundStyle(VolioTheme.blue)
                        }
                    }
                }
            }

            DetailSection("Personal Notes") {
                VStack(spacing: 0) {
                    DetailInfoRow(label: "Child Quote", value: artwork.childQuote)
                    DetailInfoRow(label: "Parent Note", value: artwork.parentNote)
                    DetailInfoRow(label: "Story", value: artwork.story)
                }
            }

            DetailSection("Artwork Info") {
                VStack(spacing: 0) {
                    DetailInfoRow(label: "Child", value: artwork.childName)
                    DetailInfoRow(label: "Date", value: artwork.artworkDate ?? artwork.dateNote ?? artwork.createdAroundLabel)
                    DetailInfoRow(label: "Batch", value: artwork.batchName)
                    DetailInfoRow(label: "Type", value: artwork.workType)
                    DetailInfoRow(label: "Stage", value: artwork.stage)
                    DetailInfoRow(label: "Medium", value: artwork.medium)
                    DetailInfoRow(label: "Size", value: imageDimensions)
                    DetailInfoRow(label: "Status", value: artwork.physicalStatus)
                    DetailInfoRow(label: "AI", value: aiStatus)
                    DetailInfoRow(label: "Locale", value: artwork.aiLocale)
                    DetailInfoRow(label: "File", value: fileName)
                    DetailInfoRow(label: "Created", value: formattedServerDate(artwork.createdAt) ?? work.createdAt.formatted(date: .abbreviated, time: .shortened))
                    DetailInfoRow(label: "Updated", value: formattedServerDate(artwork.updatedAt) ?? work.localUpdatedAt?.formatted(date: .abbreviated, time: .shortened))
                    DetailInfoRow(label: "Representative", value: (artwork.isRepresentative?.boolValue ?? work.isRepresentative) ? "Yes" : "No")
                }
            }

            DetailSection("Sync") {
                VStack(spacing: 0) {
                    DetailInfoRow(label: "Mac", value: work.remoteArtworkId == nil ? "Not synced" : "Synced")
                    DetailInfoRow(label: "Updated", value: formattedServerDate(artwork.updatedAt) ?? work.localUpdatedAt?.formatted(date: .abbreviated, time: .shortened))
                    DetailInfoRow(label: "Remote ID", value: artwork.id == work.id ? work.remoteArtworkId : artwork.id)
                    DetailInfoRow(label: "Status", value: aiStatus ?? processingTitle)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var displayTitle: String {
        clean(artwork.title) ?? clean(work.aiTitle) ?? clean(artwork.description).map { String($0.prefix(40)) } ?? "Untitled"
    }

    private var detailTags: [String] {
        var seen = Set<String>()
        return (artwork.tags ?? []).compactMap { tag in
            let value = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            let key = value.lowercased()
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return value
        }
    }

    private var imageDimensions: String? {
        if let width = artwork.width, let height = artwork.height {
            return "\(width) x \(height)"
        }
        guard let path = work.originalPath,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let image = UIImage(data: data)
        else {
            return nil
        }
        return "\(Int(image.size.width)) × \(Int(image.size.height))"
    }

    private var fileName: String? {
        if let originalFilename = clean(artwork.originalFilename) {
            return originalFilename
        }
        guard let path = work.originalPath else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var aiStatus: String? {
        let parts = [artwork.aiStatus, artwork.aiModel]
            .compactMap { clean($0) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var processingCard: some View {
        HStack(spacing: 12) {
            Image(systemName: processingIcon)
                .foregroundStyle(processingColor)
                .frame(width: 28, height: 28)
                .background(processingColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(processingTitle)
                    .font(.subheadline.weight(.semibold))
                if let error = work.processingError, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if session.isMacPaired {
                    Text("Mac Assist can add titles, descriptions, tags, and search hints.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Connect Volio Desktop to enable local AI processing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if work.processingStatus == "failed" || work.processingStatus == "waiting_for_mac" {
                Button("Retry") {
                    session.retryProcessing(work)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(14)
        .background(VolioTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private var processingIcon: String {
        switch work.processingStatus {
        case "succeeded": "checkmark.circle.fill"
        case "failed": "exclamationmark.triangle.fill"
        case "waiting_for_mac": "desktopcomputer"
        case "uploading": "arrow.up.circle.fill"
        default: "sparkles"
        }
    }

    private var processingTitle: String {
        switch work.processingStatus {
        case "succeeded": "AI summary ready"
        case "failed": "Mac Assist needs attention"
        case "waiting_for_mac": "Waiting for Mac Assist"
        case "uploading": "Sending to Mac Assist"
        case "queued": "Queued for Mac Assist"
        default: "Saved on this iPhone"
        }
    }

    private var processingColor: Color {
        switch work.processingStatus {
        case "succeeded": .green
        case "failed": .orange
        case "waiting_for_mac": .secondary
        default: accentColor
        }
    }

    private func ageLabel(_ months: Int) -> String {
        let years = max(0, months) / 12
        let extra = max(0, months) % 12
        return extra == 0 ? "Age \(years)" : "Age \(years)y \(extra)m"
    }

    private func clean(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private func formattedServerDate(_ value: String?) -> String? {
        guard let value = clean(value) else { return nil }
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date.formatted(date: .abbreviated, time: format == "yyyy-MM-dd" ? .omitted : .shortened)
            }
        }
        if let date = ISO8601DateFormatter().date(from: value) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return value
    }
}

private struct DetailSection<Content: View>: View {
    var title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(VolioTheme.mutedInk)
                .textCase(.uppercase)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(VolioTheme.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                }
        }
    }
}

private struct DetailInfoRow: View {
    var label: String
    var value: String?

    private var displayValue: String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return "Not set"
        }
        return value
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VolioTheme.mutedInk)
                .frame(width: 116, alignment: .leading)
            Text(displayValue)
                .font(.subheadline)
                .foregroundStyle(displayValue == "Not set" ? VolioTheme.mutedInk.opacity(0.68) : VolioTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 1)
        }
    }
}

// MARK: - Editor

struct ArtworkEditorView: View {
    @Environment(VolioSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State var work: LocalWork
    @State private var title: String
    @State private var note: String
    @State private var childQuote: String
    @State private var showDeleteConfirmation = false
    var onSave: (LocalWork) -> Void
    var onDelete: () -> Void

    init(work: LocalWork, onSave: @escaping (LocalWork) -> Void, onDelete: @escaping () -> Void) {
        self.work = work
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: work.title ?? "")
        _note = State(initialValue: work.note ?? "")
        _childQuote = State(initialValue: work.childQuote ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                } header: {
                    Label("Artwork", systemImage: "paintbrush")
                }

                Section {
                    TextField("Their words…", text: $childQuote, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Your note…", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Label("Story", systemImage: "text.quote")
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Work", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        session.updateWork(work, title: title, note: note, childQuote: childQuote)
                        work.title = title.isEmpty ? nil : title
                        work.note = note.isEmpty ? nil : note
                        work.childQuote = childQuote.isEmpty ? nil : childQuote
                        onSave(work)
                        dismiss()
                    }
                }
            }
            .volioDeleteConfirmation(isPresented: $showDeleteConfirmation, count: 1) {
                onDelete()
                dismiss()
            }
        }
    }
}

extension View {
    func volioDeleteConfirmation(
        isPresented: Binding<Bool>,
        count: Int,
        action: @escaping () -> Void
    ) -> some View {
        alert(deleteTitle(count: count), isPresented: isPresented) {
            Button("Delete", role: .destructive, action: action)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage(count: count))
        }
    }

    private func deleteTitle(count: Int) -> String {
        count == 1 ? "Delete this work?" : "Delete \(count) works?"
    }

    private func deleteMessage(count: Int) -> String {
        if count == 1 {
            return "This removes the local work and asks Volio Desktop to delete its synced copy if one exists."
        }
        return "This removes the selected works and asks Volio Desktop to delete synced copies if they exist."
    }
}
