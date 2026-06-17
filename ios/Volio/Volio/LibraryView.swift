import SwiftUI

struct LibraryView: View {
    @Environment(VolioSession.self) private var session
    @State private var searchText = ""

    private let columns = [
        GridItem(.adaptive(minimum: 112), spacing: 12)
    ]

    private var filteredWorks: [Artwork] {
        guard !searchText.isEmpty else { return session.artworks }
        let query = searchText.lowercased()
        return session.artworks.filter { work in
            (work.title ?? "").lowercased().contains(query)
            || (work.description ?? "").lowercased().contains(query)
            || (work.childName ?? "").lowercased().contains(query)
            || (work.childAgeLabel ?? "").lowercased().contains(query)
            || (work.createdAroundLabel ?? "").lowercased().contains(query)
            || (work.workType ?? "").lowercased().contains(query)
            || (work.medium ?? "").lowercased().contains(query)
            || (work.tags ?? []).contains { $0.name.lowercased().contains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredWorks) { work in
                        NavigationLink(value: work) {
                            ArtworkTile(work: work)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Library")
            .searchable(text: $searchText)
            .navigationDestination(for: Artwork.self) { work in
                ArtworkDetailView(artwork: work)
            }
            .refreshable {
                await session.refresh()
            }
        }
    }
}

struct ArtworkTile: View {
    var work: Artwork

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            AsyncImage(url: URL(string: work.thumbnailAbsoluteURL ?? work.displayAbsoluteURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "photo").font(.title2).foregroundStyle(.secondary)
                default:
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(work.title?.isEmpty == false ? work.title! : "Untitled")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text([work.childAgeLabel ?? work.createdAroundLabel, work.childName].compactMap { $0 }.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
