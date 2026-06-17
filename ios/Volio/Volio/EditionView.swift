import SwiftUI
import UniformTypeIdentifiers

struct EditionView: View {
    @Environment(VolioSession.self) private var session
    @State private var showingCreateSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if session.editions.isEmpty {
                    emptyState
                } else {
                    editionList
                }
            }
            .navigationTitle("Editions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(session.artworks.isEmpty)
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateEditionView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No editions yet")
                .font(.title3.weight(.semibold))
            Text("Create an edition to see what a collection of works looks like together.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            if !session.artworks.isEmpty {
                Button {
                    showingCreateSheet = true
                } label: {
                    Label("Create an Edition", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var editionList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(session.editions) { edition in
                    NavigationLink(destination: EditionDetailView(edition: edition)) {
                        EditionListCard(edition: edition)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
}

private struct EditionListCard: View {
    @Environment(VolioSession.self) private var session
    let edition: Edition

    var body: some View {
        HStack(spacing: 14) {
            coverView
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(edition.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let subtitle = edition.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("\(edition.workCount) works")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var coverView: some View {
        if let coverId = edition.coverWorkId,
           let work = session.artworks.first(where: { $0.id == coverId }),
           let urlStr = work.thumbnailAbsoluteURL ?? work.displayAbsoluteURL {
            AsyncImage(url: URL(string: urlStr)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Rectangle().fill(.quaternary)
                }
            }
        } else {
            Rectangle().fill(.quaternary)
        }
    }
}

// MARK: - Create

struct CreateEditionView: View {
    @Environment(VolioSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var selectedGroup: String = ""
    @State private var customTitle = ""
    @State private var selectedWorkIds: Set<String> = []

    private var groups: [(key: String, works: [Artwork])] {
        let grouped = Dictionary(grouping: session.artworks) { work in
            if let age = work.childAgeMonths {
                return "Age \(max(0, age) / 12)"
            }
            if let year = work.artworkDate?.prefix(4), !year.isEmpty {
                return String(year)
            }
            return "Other"
        }
        return grouped.map { ($0.key, $0.value) }.sorted { $0.key > $1.key }
    }

    private var selectedWorks: [Artwork] {
        session.artworks.filter { selectedWorkIds.contains($0.id) }
    }

    private var generatedTitle: String {
        if !customTitle.trimmingCharacters(in: .whitespaces).isEmpty {
            return customTitle.trimmingCharacters(in: .whitespaces)
        }
        return "\(selectedGroup) Edition"
    }

    private var canCreate: Bool {
        !selectedGroup.isEmpty && !selectedWorkIds.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Choose a time period") {
                    Picker("Period", selection: $selectedGroup) {
                        Text("Select").tag("")
                        ForEach(groups, id: \.key) { group in
                            Text(group.key).tag(group.key)
                        }
                    }
                    .onChange(of: selectedGroup) { _, newValue in
                        if let group = groups.first(where: { $0.key == newValue }) {
                            selectedWorkIds = Set(group.works.map(\.id))
                        }
                    }
                }

                if !selectedWorkIds.isEmpty {
                    Section("Title") {
                        TextField("Edition title", text: $customTitle)
                            .textInputAutocapitalization(.words)
                        Text("\(generatedTitle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Works (\(selectedWorkIds.count))") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(selectedWorks.prefix(20)) { work in
                                    if let urlStr = work.thumbnailAbsoluteURL ?? work.displayAbsoluteURL {
                                        AsyncImage(url: URL(string: urlStr)) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image.resizable().scaledToFill()
                                                    .frame(width: 56, height: 56)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                            default:
                                                Rectangle().fill(.quaternary)
                                                    .frame(width: 56, height: 56)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                            }
                                        }
                                    }
                                }
                                if selectedWorks.count > 20 {
                                    Text("+\(selectedWorks.count - 20) more")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(height: 64)
                    }
                }
            }
            .navigationTitle("Create Edition")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        create()
                    }
                    .disabled(!canCreate)
                }
            }
        }
    }

    private func create() {
        let coverId = selectedWorks.first?.id
        let creatorName: String? = {
            if let first = selectedWorks.first, let name = first.childName {
                return name
            }
            return nil
        }()
        _ = session.createEdition(
            title: generatedTitle,
            subtitle: selectedGroup,
            workIds: Array(selectedWorkIds),
            coverWorkId: coverId,
            creatorName: creatorName
        )
        dismiss()
    }
}

// MARK: - Detail

struct EditionDetailView: View {
    @Environment(VolioSession.self) private var session
    let edition: Edition
    @State private var isExporting = false
    @State private var exportError: String?

    private var page: EditionPage {
        session.editionPage(for: edition)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                coverSection
                worksSection
            }
            .padding(16)
        }
        .navigationTitle(edition.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    shareEdition()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                Button {
                    exportPDF()
                } label: {
                    if isExporting {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.down.doc")
                    }
                }
                .disabled(isExporting)
            }
        }
        .alert("Export Error", isPresented: .init(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var coverSection: some View {
        VStack(spacing: 12) {
            if let cover = page.coverWork, let urlStr = cover.displayAbsoluteURL ?? cover.originalAbsoluteURL {
                AsyncImage(url: URL(string: urlStr)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    default:
                        Rectangle().fill(.quaternary)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            }

            VStack(spacing: 6) {
                Text(edition.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                if let subtitle = edition.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("\(edition.workCount) works")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if let name = edition.creatorName {
                    Text(name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var worksSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
            ForEach(page.works) { work in
                NavigationLink(value: work) {
                    VStack(spacing: 6) {
                        if let urlStr = work.thumbnailAbsoluteURL ?? work.displayAbsoluteURL {
                            AsyncImage(url: URL(string: urlStr)) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                default:
                                    Rectangle().fill(.quaternary)
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        Text(work.title ?? "Untitled")
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func shareEdition() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let root = window.rootViewController else { return }
        let text = "\(edition.title) — \(edition.workCount) works"
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        root.present(activityVC, animated: true)
    }

    private func exportPDF() {
        isExporting = true
        Task {
            do {
                let works = page.works
                var images: [String: Data] = [:]
                for work in works {
                    if let urlStr = work.displayAbsoluteURL ?? work.originalAbsoluteURL,
                       let url = URL(string: urlStr),
                       let (data, _) = try? await URLSession.shared.data(from: url) {
                        images[work.id] = data
                    }
                }
                let url = try await generatePDF(works: works, images: images)
                await MainActor.run {
                    isExporting = false
                    presentShareSheet(url: url)
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                }
            }
        }
    }

    private func generatePDF(works: [Artwork], images: [String: Data]) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(edition.title).pdf")
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 48

        UIGraphicsBeginPDFContextToFile(url.path, CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), nil)
        defer { UIGraphicsEndPDFContext() }

        // Cover page
        UIGraphicsBeginPDFPage()
        let ctx = UIGraphicsGetCurrentContext()!
        let titleFont = UIFont.boldSystemFont(ofSize: 34)
        let subtitleFont = UIFont.systemFont(ofSize: 18)
        let bodyFont = UIFont.systemFont(ofSize: 14)

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: UIColor.black]
        let titleSize = (edition.title as NSString).size(withAttributes: titleAttrs)
        (edition.title as NSString).draw(
            at: CGPoint(x: (pageWidth - titleSize.width) / 2, y: pageHeight / 2 - 60),
            withAttributes: titleAttrs
        )

        // Subtitle
        if let subtitle = edition.subtitle {
            let subAttrs: [NSAttributedString.Key: Any] = [.font: subtitleFont, .foregroundColor: UIColor.secondaryLabel]
            let subSize = (subtitle as NSString).size(withAttributes: subAttrs)
            (subtitle as NSString).draw(
                at: CGPoint(x: (pageWidth - subSize.width) / 2, y: pageHeight / 2),
                withAttributes: subAttrs
            )
        }

        // Work count
        let countText = "\(works.count) works"
        let countAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: UIColor.tertiaryLabel]
        let countSize = (countText as NSString).size(withAttributes: countAttrs)
        (countText as NSString).draw(
            at: CGPoint(x: (pageWidth - countSize.width) / 2, y: pageHeight / 2 + 40),
            withAttributes: countAttrs
        )

        // Footer
        let footer = "Created with Volio"
        let footerAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.tertiaryLabel]
        let footerSize = (footer as NSString).size(withAttributes: footerAttrs)
        (footer as NSString).draw(
            at: CGPoint(x: (pageWidth - footerSize.width) / 2, y: pageHeight - 40),
            withAttributes: footerAttrs
        )

        // Work pages
        let workFont = UIFont.boldSystemFont(ofSize: 16)
        let descFont = UIFont.systemFont(ofSize: 12)
        let labelWidth = pageWidth - margin * 2
        let imageMaxHeight: CGFloat = 500

        for work in works {
            UIGraphicsBeginPDFPage()

            if let imageData = images[work.id], let image = UIImage(data: imageData) {
                let imgW = image.size.width
                let imgH = image.size.height
                let scale = min(imageMaxHeight / imgH, labelWidth / imgW, 1.0)
                let drawW = imgW * scale
                let drawH = imgH * scale
                image.draw(in: CGRect(x: (pageWidth - drawW) / 2, y: margin, width: drawW, height: drawH))

                // Title below image
                let workTitle = work.title ?? "Untitled"
                let workTitleAttrs: [NSAttributedString.Key: Any] = [.font: workFont, .foregroundColor: UIColor.black]
                let wtSize = (workTitle as NSString).size(withAttributes: workTitleAttrs)
                let wtX = max(margin, (pageWidth - wtSize.width) / 2)
                (workTitle as NSString).draw(at: CGPoint(x: wtX, y: margin + drawH + 16), withAttributes: workTitleAttrs)

                // Description
                if let desc = work.description, !desc.isEmpty {
                    let descAttrs: [NSAttributedString.Key: Any] = [.font: descFont, .foregroundColor: UIColor.secondaryLabel]
                    let descRect = CGRect(x: margin, y: margin + drawH + 44, width: labelWidth, height: 60)
                    (desc as NSString).draw(with: descRect, options: .usesLineFragmentOrigin, attributes: descAttrs, context: nil)
                }
            } else {
                // No image placeholder
                let workTitle = work.title ?? "Untitled"
                let noImgFont = UIFont.italicSystemFont(ofSize: 14)
                let noImgAttrs: [NSAttributedString.Key: Any] = [.font: noImgFont, .foregroundColor: UIColor.tertiaryLabel]
                let noImgSize = ("[\(workTitle)]" as NSString).size(withAttributes: noImgAttrs)
                ("[\(workTitle)]" as NSString).draw(
                    at: CGPoint(x: (pageWidth - noImgSize.width) / 2, y: pageHeight / 2),
                    withAttributes: noImgAttrs
                )
            }

            // Footer
            (footer as NSString).draw(
                at: CGPoint(x: (pageWidth - footerSize.width) / 2, y: pageHeight - 40),
                withAttributes: footerAttrs
            )
        }

        return url
    }

    private func presentShareSheet(url: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let root = window.rootViewController else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        root.present(activityVC, animated: true)
    }
}

#Preview {
    EditionView()
        .environment(VolioSession())
}
