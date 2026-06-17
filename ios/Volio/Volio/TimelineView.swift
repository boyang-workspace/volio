import SwiftUI

private struct TimelineGroup: Identifiable {
    var id: String { title }
    let title: String
    let subtitle: String
    let sortKey: Int
    let works: [Artwork]
}

struct TimelineView: View {
    @Environment(VolioSession.self) private var session

    private var selectedChild: Child? {
        session.children.first(where: { $0.id == session.selectedChildId }) ?? session.children.first
    }

    private var visibleWorks: [Artwork] {
        guard let selectedChild else { return session.artworks }
        return session.artworks.filter { $0.childId == selectedChild.id }
    }

    private var groups: [TimelineGroup] {
        let grouped = Dictionary(grouping: visibleWorks) { work in
            work.timelineGroup ?? fallbackGroup(for: work)
        }
        return grouped.map { title, works in
            let sortedWorks = works.sorted { ($0.artworkDate ?? $0.createdAroundLabel ?? "") > ($1.artworkDate ?? $1.createdAroundLabel ?? "") }
            let maxAge = sortedWorks.compactMap(\.childAgeMonths).max()
            let year = sortedWorks.compactMap { Int(($0.artworkDate ?? "").prefix(4)) }.max()
            return TimelineGroup(
                title: title,
                subtitle: groupSubtitle(for: sortedWorks),
                sortKey: maxAge ?? ((year ?? 0) * 12),
                works: sortedWorks
            )
        }
        .sorted { $0.sortKey > $1.sortKey }
    }

    private var thenNow: (Artwork, Artwork, String)? {
        let works = visibleWorks
            .filter { ($0.childAgeMonths ?? -1) >= 0 }
            .sorted { ($0.childAgeMonths ?? 0) < ($1.childAgeMonths ?? 0) }
        for first in works {
            guard let firstAge = first.childAgeMonths else { continue }
            let firstTags = Set((first.tags ?? []).map(\.name))
            guard !firstTags.isEmpty else { continue }
            if let latest = works.reversed().first(where: { candidate in
                guard let latestAge = candidate.childAgeMonths, latestAge - firstAge >= 6 else { return false }
                return !(Set((candidate.tags ?? []).map(\.name)).intersection(firstTags).isEmpty)
            }) {
                let tag = Set((latest.tags ?? []).map(\.name)).intersection(firstTags).sorted().first ?? "same theme"
                return (first, latest, tag)
            }
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    header
                    queueStrip
                    if let thenNow {
                        ThenNowCard(first: thenNow.0, latest: thenNow.1, label: thenNow.2)
                    }
                    timeline
                }
                .padding(18)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Timeline")
            .navigationDestination(for: Artwork.self) { work in
                ArtworkDetailView(artwork: work)
            }
            .refreshable {
                await session.refresh()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    childMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await session.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(selectedChild?.name ?? "All children")
                        .font(.title.bold())
                    Text(summaryLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.blue)
            }

            HStack(spacing: 10) {
                StatPill(value: "\(visibleWorks.count)", label: "works")
                StatPill(value: "\(groups.count)", label: "ages")
                StatPill(value: "\(favoriteCount)", label: "favorites")
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26)
        )
    }

    @ViewBuilder
    private var queueStrip: some View {
        if let queue = session.queue, queue.pending + queue.processing + queue.failed > 0 {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Organizing on Volio Desktop")
                        .font(.subheadline.weight(.semibold))
                    Text("Processing \(queue.processing) · Waiting \(queue.pending) · Failed \(queue.failed)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                AgeTimelineSection(group: group, isLast: index == groups.count - 1)
            }
        }
    }

    private var childMenu: some View {
        Menu {
            ForEach(session.children) { child in
                Button(child.name) {
                    session.selectedChildId = child.id
                }
            }
        } label: {
            Label(selectedChild?.name ?? "Child", systemImage: "person.crop.circle")
                .font(.subheadline.weight(.semibold))
        }
    }

    private var summaryLine: String {
        guard !visibleWorks.isEmpty else { return "Capture a pile to build the first age timeline." }
        let labels = groups.prefix(2).map(\.title).joined(separator: " and ")
        return labels.isEmpty ? "Artwork timeline is ready." : "Artwork organized across \(labels)."
    }

    private var favoriteCount: Int {
        visibleWorks.filter { $0.isFavorite?.boolValue == true }.count
    }

    private func fallbackGroup(for work: Artwork) -> String {
        if let age = work.childAgeMonths {
            return "Age \(max(0, age) / 12)"
        }
        if let year = work.artworkDate?.prefix(4), !year.isEmpty {
            return String(year)
        }
        return "Date unknown"
    }

    private func groupSubtitle(for works: [Artwork]) -> String {
        let dates = Set(works.compactMap(\.createdAroundLabel)).sorted()
        if let first = dates.first, dates.count == 1 {
            return "\(works.count) works · \(first)"
        }
        return "\(works.count) works"
    }
}

private struct AgeTimelineSection: View {
    var group: TimelineGroup
    var isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(.blue)
                    .frame(width: 13, height: 13)
                    .overlay {
                        Circle().stroke(.blue.opacity(0.2), lineWidth: 6)
                    }
                    .padding(.top, 8)
                if !isLast {
                    Rectangle()
                        .fill(.blue.opacity(0.2))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title)
                        .font(.title3.bold())
                    Text(group.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                    ForEach(group.works.prefix(8)) { work in
                        NavigationLink(value: work) {
                            TimelineThumb(work: work)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
            .padding(.bottom, isLast ? 0 : 18)
        }
    }
}

private struct TimelineThumb: View {
    var work: Artwork

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: URL(string: work.thumbnailAbsoluteURL ?? work.displayAbsoluteURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "photo").foregroundStyle(.secondary)
                default:
                    ProgressView()
                }
            }
            .frame(height: 92)
            .frame(maxWidth: .infinity)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Text(work.title?.isEmpty == false ? work.title! : "Untitled")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
    }
}

private struct ThenNowCard: View {
    var first: Artwork
    var latest: Artwork
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Then & Now · \(label)", systemImage: "rectangle.split.2x1")
                .font(.headline)
            HStack(spacing: 12) {
                CompareWork(work: first, caption: first.childAgeLabel ?? "Earlier")
                CompareWork(work: latest, caption: latest.childAgeLabel ?? "Later")
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct CompareWork: View {
    var work: Artwork
    var caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: URL(string: work.thumbnailAbsoluteURL ?? work.displayAbsoluteURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "photo").foregroundStyle(.secondary)
                default:
                    ProgressView()
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(caption)
                .font(.caption.weight(.semibold))
            Text(work.title ?? "Untitled")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatPill: View {
    var value: String
    var label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ArtworkRow: View {
    var work: Artwork

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: work.thumbnailAbsoluteURL ?? work.displayAbsoluteURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "photo").foregroundStyle(.secondary)
                default:
                    ProgressView()
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(work.title?.isEmpty == false ? work.title! : "Untitled artwork")
                    .font(.body.weight(.semibold))
                Text([work.childName, work.childAgeLabel ?? work.createdAroundLabel, work.aiStatus].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let description = work.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}
