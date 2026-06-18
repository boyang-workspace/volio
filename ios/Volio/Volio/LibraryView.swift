import SwiftUI

struct LibraryView: View {
    @Environment(VolioSession.self) private var session
    @State private var searchText = ""
    @State private var selectedIds = Set<String>()
    @State private var isSelecting = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 10)]

    private var filteredWorks: [LocalWork] {
        guard !searchText.isEmpty else { return session.works }
        let query = searchText.lowercased()
        return session.works.filter { work in
            work.searchableText.lowercased().contains(query)
        }
    }

    private var filteredMacWorks: [Artwork] {
        guard !searchText.isEmpty else { return session.macArtworks }
        let query = searchText.lowercased()
        return session.macArtworks.filter { work in
            [
                work.title,
                work.description,
                work.longDescription,
                work.childQuote,
                work.parentNote,
                work.createdAroundLabel,
                work.childAgeLabel,
                work.tags?.map(\.name).joined(separator: " ")
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if filteredWorks.isEmpty && filteredMacWorks.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        if !filteredWorks.isEmpty {
                            librarySectionTitle("On this iPhone", count: filteredWorks.count)
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(filteredWorks) { work in
                                    if isSelecting {
                                        selectableTile(work: work)
                                    } else {
                                        NavigationLink(value: work) {
                                            LibraryTile(work: work)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        if !filteredMacWorks.isEmpty {
                            librarySectionTitle("On Mac", count: filteredMacWorks.count)
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(filteredMacWorks) { work in
                                    RemoteLibraryTile(work: work)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .background(VolioTheme.paper)
            .navigationTitle("Library")
            .searchable(text: $searchText)
            .navigationDestination(for: LocalWork.self) { work in
                ArtworkDetailView(work: work)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        if session.isMacPaired {
                            Button {
                                Task { await session.refreshMacLibrary(showError: true) }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        if !session.works.isEmpty {
                            Button(isSelecting ? "Done" : "Select") {
                                isSelecting.toggle()
                                if !isSelecting { selectedIds.removeAll() }
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if isSelecting && !selectedIds.isEmpty {
                    HStack(spacing: 14) {
                        Button(role: .destructive) {
                            deleteSelected()
                        } label: {
                            Label("Delete (\(selectedIds.count))", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.large)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "rectangle.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text(searchText.isEmpty ? "No works yet" : "No results")
                .font(.title3.weight(.semibold))
            Text(searchText.isEmpty ? "Capture your first work to build your library." : "Try a different search.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private func librarySectionTitle(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func selectableTile(work: LocalWork) -> some View {
        let isSelected = selectedIds.contains(work.id)
        return LibraryTile(work: work)
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .white.opacity(0.7))
                    .shadow(radius: 1)
                    .padding(6)
            }
            .onTapGesture {
                if isSelected {
                    selectedIds.remove(work.id)
                } else {
                    selectedIds.insert(work.id)
                }
            }
    }

    private func deleteSelected() {
        for id in selectedIds {
            if let work = session.works.first(where: { $0.id == id }) {
                session.deleteWork(work)
            }
        }
        selectedIds.removeAll()
        isSelecting = false
    }
}

private struct LibraryTile: View {
    var work: LocalWork

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalThumbnail(path: work.thumbnailPath ?? work.originalPath, workId: work.id)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(work.displayTitle)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Text(work.createdAroundLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }
}

private struct RemoteLibraryTile: View {
    var work: Artwork

    private var url: URL? {
        let raw = work.originalAbsoluteURL
        return raw.flatMap(URL.init(string:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    placeholder.overlay {
                        ProgressView()
                    }
                @unknown default:
                    placeholder
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(work.title ?? "Untitled")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Text(work.createdAroundLabel ?? work.artworkDate ?? "On Mac")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: "desktopcomputer")
                    .foregroundStyle(.tertiary)
            }
    }
}
