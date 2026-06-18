import SwiftUI
import UIKit

struct VolioPageHeader<Actions: View>: View {
    var title: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(VolioTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .padding(.top, 18)
        .modifier(AppStoreHeaderMotion())
    }
}

private struct AppStoreHeaderMotion: ViewModifier {
    func body(content: Content) -> some View {
        content.visualEffect { visualContent, proxy in
            visualContent
                .offset(y: Self.offset(for: proxy))
                .opacity(Self.opacity(for: proxy))
                .scaleEffect(Self.scale(for: proxy), anchor: .bottomLeading)
        }
    }

    nonisolated private static func progress(for proxy: GeometryProxy) -> CGFloat {
        min(max(-proxy.frame(in: .scrollView).minY / 84, 0), 1)
    }

    nonisolated private static func offset(for proxy: GeometryProxy) -> CGFloat {
        let minY = proxy.frame(in: .scrollView).minY
        return minY < 0 ? minY * 0.28 : 0
    }

    nonisolated private static func opacity(for proxy: GeometryProxy) -> CGFloat {
        1 - progress(for: proxy) * 0.92
    }

    nonisolated private static func scale(for proxy: GeometryProxy) -> CGFloat {
        1 - progress(for: proxy) * 0.035
    }
}

struct GalleryView: View {
    @Environment(VolioSession.self) private var session
    @State private var showSettings = false
    @State private var selectedIds = Set<String>()
    @State private var isSelecting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VolioPageHeader(title: "Gallery") {
                        headerActions
                    }

                    if session.works.isEmpty {
                        emptyState
                    } else {
                        MasonryGrid(works: session.works, isSelecting: isSelecting, selectedIds: selectedIds) { work in
                            toggleSelection(work)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, isSelecting && !selectedIds.isEmpty ? 132 : 96)
            }
            .background(VolioTheme.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await session.refreshLibrary(showError: true)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsContent() }
            }
            .navigationDestination(for: LocalWork.self) { work in
                ArtworkDetailView(work: work)
            }
            .overlay(alignment: .bottom) {
                if isSelecting && !selectedIds.isEmpty {
                    selectionBar
                }
            }
        }
    }

    private var headerActions: some View {
        HStack(spacing: 8) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .volioGlass(cornerRadius: 19, interactive: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var galleryActions: some View {
        HStack {
            Spacer()
            Button(isSelecting ? "Done" : "Select") {
                isSelecting.toggle()
                if !isSelecting { selectedIds.removeAll() }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(height: 38)
            .volioGlass(cornerRadius: 19, interactive: true)
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 120)
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("Start with one work")
                .font(.title3.weight(.semibold))
            Text("Scan a stack and Volio will organize it by real creation age.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var selectionBar: some View {
        HStack(spacing: 14) {
            Button(role: .destructive) {
                deleteSelected()
            } label: {
                Label("Delete \(selectedIds.count)", systemImage: "trash")
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

    private func toggleSelection(_ work: LocalWork) {
        if selectedIds.contains(work.id) {
            selectedIds.remove(work.id)
        } else {
            selectedIds.insert(work.id)
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

struct TimelineView: View {
    @Environment(VolioSession.self) private var session
    @State private var showSettings = false

    private var groups: [(title: String, subtitle: String, works: [LocalWork])] {
        let grouped = Dictionary(grouping: session.works) { work in
            work.timelineGroupTitle
        }
        return grouped.map { title, works in
            let sorted = works.sorted { $0.capturedAt > $1.capturedAt }
            let subtitle = sorted.first?.createdAroundLabel ?? ""
            return (title, subtitle, sorted)
        }
        .sorted { left, right in
            groupSortValue(left.title, works: left.works) > groupSortValue(right.title, works: right.works)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    VolioPageHeader(title: "Timeline") {
                        headerActions
                    }
                    .padding(.horizontal, 18)

                    if session.works.isEmpty {
                        ContentUnavailableView("No timeline yet", systemImage: "clock", description: Text("Capture or sync works to build a creative timeline."))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 120)
                    } else {
                        ForEach(groups, id: \.title) { group in
                            TimelineAgeSection(title: group.title, subtitle: group.subtitle, works: group.works)
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 96)
            }
            .background(VolioTheme.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await session.refreshLibrary(showError: true)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsContent() }
            }
            .navigationDestination(for: LocalWork.self) { work in
                ArtworkDetailView(work: work)
            }
        }
    }

    private var headerActions: some View {
        HStack(spacing: 8) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .volioGlass(cornerRadius: 19, interactive: true)
            }
            .buttonStyle(.plain)
        }
    }

    private func groupSortValue(_ title: String, works: [LocalWork]) -> TimeInterval {
        if title.hasPrefix("Age "), let years = Int(title.replacingOccurrences(of: "Age ", with: "")) {
            return TimeInterval(10_000_000 + years)
        }
        if let year = Int(title) {
            return TimeInterval(year)
        }
        return works.first?.capturedAt.timeIntervalSince1970 ?? 0
    }
}

struct MasonryGrid: View {
    var works: [LocalWork]
    var isSelecting = false
    var selectedIds = Set<String>()
    var onToggleSelection: (LocalWork) -> Void = { _ in }

    var body: some View {
        PinterestMasonryLayout(columns: 2, spacing: 10) {
            ForEach(works) { work in
                if isSelecting {
                    MasonryTile(work: work)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: selectedIds.contains(work.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selectedIds.contains(work.id) ? VolioTheme.accent : .white.opacity(0.84))
                                .shadow(radius: 1)
                                .padding(6)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { onToggleSelection(work) }
                } else {
                    NavigationLink(value: work) {
                        MasonryTile(work: work)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct MasonryTile: View {
    var work: LocalWork
    @State private var displayAspectRatio: CGFloat = 0.78

    var body: some View {
        MasonryImage(
            workId: work.id,
            primaryPath: work.thumbnailPath,
            fallbackPath: work.originalPath,
            displayAspectRatio: $displayAspectRatio
        )
            .aspectRatio(displayAspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
    }
}

struct MasonryImage: View {
    var workId: String?
    var primaryPath: String?
    var fallbackPath: String?
    @Binding var displayAspectRatio: CGFloat
    @State private var image: UIImage?
    @State private var loadKey: String?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .aspectRatio(displayAspectRatio, contentMode: .fill)
        .clipped()
        .task(id: "\(workId ?? "")|\(primaryPath ?? "")|\(fallbackPath ?? "")") {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        let key = "\(workId ?? "")|\(primaryPath ?? "")|\(fallbackPath ?? "")"
        guard loadKey != key else { return }
        loadKey = key
        image = nil
        let candidates = [
            workId.map(ImageStorage.thumbnailPath(for:)),
            workId.map(ImageStorage.originalPath(for:)),
            primaryPath,
            fallbackPath,
            inferredOriginalPath(from: primaryPath)
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        let loaded = await Task.detached(priority: .utility) { () -> UIImage? in
            for path in candidates {
                if FileManager.default.fileExists(atPath: path),
                   let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                   let image = UIImage(data: data) {
                    return image
                }
            }
            return nil as UIImage?
        }.value
        if loadKey == key {
            if let loaded {
                let rawRatio = max(0.1, loaded.size.width / max(loaded.size.height, 1))
                displayAspectRatio = max(rawRatio, 0.68)
            }
            image = loaded
        }
    }

    private func inferredOriginalPath(from path: String?) -> String? {
        guard let path, path.hasSuffix("thumbnail.jpg") else { return nil }
        return URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("original.jpg").path
    }
}

private struct PinterestMasonryLayout: Layout {
    var columns: Int = 2
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        guard width > 0, !subviews.isEmpty else {
            return CGSize(width: width, height: 0)
        }

        let columnCount = max(1, columns)
        let columnWidth = (width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        var heights = Array(repeating: CGFloat.zero, count: columnCount)

        for subview in subviews {
            let targetColumn = shortestColumn(in: heights)
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            if heights[targetColumn] > 0 {
                heights[targetColumn] += spacing
            }
            heights[targetColumn] += size.height
        }

        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard bounds.width > 0 else { return }

        let columnCount = max(1, columns)
        let columnWidth = (bounds.width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        var heights = Array(repeating: bounds.minY, count: columnCount)

        for subview in subviews {
            let targetColumn = shortestColumn(in: heights)
            let x = bounds.minX + CGFloat(targetColumn) * (columnWidth + spacing)
            let y = heights[targetColumn]
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: columnWidth, height: size.height)
            )
            heights[targetColumn] += size.height + spacing
        }
    }

    private func shortestColumn(in heights: [CGFloat]) -> Int {
        heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
    }
}

struct SearchView: View {
    @Environment(VolioSession.self) private var session
    @State private var query = ""
    @State private var semanticEnabled = true

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var results: [LocalWork] {
        guard !normalizedQuery.isEmpty else { return [] }
        return session.works.filter { work in
            if work.searchableText.lowercased().contains(normalizedQuery) {
                return true
            }
            if semanticEnabled {
                return semanticTokens(for: normalizedQuery).contains { token in
                    work.searchableText.lowercased().contains(token)
                }
            }
            return false
        }
    }

    private var suggestions: [String] {
        let values = session.works.flatMap { work -> [String] in
            [
                work.timelineGroupTitle,
                work.workType.capitalized,
                work.aiTags,
                work.aiMaterials,
                work.aiThemes,
                work.aiColors
            ]
            .compactMap { $0 }
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",，")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        }
        return Array(NSOrderedSet(array: values)).compactMap { $0 as? String }.prefix(12).map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VolioPageHeader(title: "Search") { EmptyView() }
                    searchField
                    semanticCard
                    recommendationSection
                    resultSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 96)
            }
            .background(VolioTheme.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LocalWork.self) { work in
                ArtworkDetailView(work: work)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(VolioTheme.mutedInk)
            TextField("Search whale, watercolor, Age 6...", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(VolioTheme.mutedInk.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, 14)
        .frame(height: 48)
        .volioGlass(cornerRadius: 18, tint: Color.white.opacity(0.40), interactive: true)
    }

    private var semanticCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Semantic Search", systemImage: "sparkle.magnifyingglass")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(VolioTheme.ink)
                Spacer()
                Toggle("", isOn: $semanticEnabled)
                    .labelsHidden()
                    .tint(VolioTheme.accent)
            }
            Text("Search across AI descriptions, tags, materials, colors, age, and notes. A Mac semantic index can plug into this same page next.")
                .font(.subheadline)
                .foregroundStyle(VolioTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(VolioTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.65), lineWidth: 1)
        }
    }

    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recommended")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(VolioTheme.mutedInk)
                .textCase(.uppercase)

            if suggestions.isEmpty {
                Text("AI tags, ages, materials, and themes will appear here after more works are analyzed.")
                    .font(.subheadline)
                    .foregroundStyle(VolioTheme.mutedInk)
            } else {
                FlowLayout(spacing: 8, rowSpacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            query = suggestion
                        } label: {
                            Text(suggestion)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(VolioTheme.blue.opacity(0.11), in: Capsule())
                                .foregroundStyle(VolioTheme.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(normalizedQuery.isEmpty ? "Start Searching" : "\(results.count) Results")
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(VolioTheme.mutedInk)
                    .textCase(.uppercase)
                Spacer()
            }

            if normalizedQuery.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    quickQuery("6 year old watercolor")
                    quickQuery("ocean animals")
                    quickQuery("favorites")
                    quickQuery("physical copy kept")
                }
            } else if results.isEmpty {
                ContentUnavailableView("No results", systemImage: "magnifyingglass", description: Text("Try a theme, material, age, color, or a phrase from notes."))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 10)], spacing: 12) {
                    ForEach(results) { work in
                        NavigationLink(value: work) {
                            MasonryTile(work: work)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func quickQuery(_ value: String) -> some View {
        Button {
            query = value
        } label: {
            HStack {
                Image(systemName: "magnifyingglass")
                Text(value)
                Spacer()
                Image(systemName: "arrow.up.left")
                    .foregroundStyle(VolioTheme.mutedInk.opacity(0.6))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(VolioTheme.ink)
            .padding(12)
            .background(VolioTheme.card, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func semanticTokens(for query: String) -> [String] {
        let lower = query.lowercased()
        var tokens = lower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
        if lower.contains("watercolor") { tokens.append("water") }
        if lower.contains("favorite") { tokens.append("true") }
        if lower.contains("physical") { tokens.append("kept") }
        return tokens
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let rows = rows(in: width, subviews: subviews)
        return CGSize(width: width, height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * rowSpacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(in: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [(items: [(subview: LayoutSubview, size: CGSize)], height: CGFloat)] {
        var rows: [(items: [(subview: LayoutSubview, size: CGSize)], height: CGFloat)] = []
        var current: [(subview: LayoutSubview, size: CGSize)] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth = current.isEmpty ? size.width : currentWidth + spacing + size.width
            if proposedWidth > width, !current.isEmpty {
                rows.append((current, currentHeight))
                current = [(subview, size)]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                current.append((subview, size))
                currentWidth = proposedWidth
                currentHeight = max(currentHeight, size.height)
            }
        }
        if !current.isEmpty {
            rows.append((current, currentHeight))
        }
        return rows
    }
}

private struct TimelineAgeSection: View {
    var title: String
    var subtitle: String
    var works: [LocalWork]

    private let columns = [GridItem(.adaptive(minimum: 86), spacing: 8)]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 5) {
                Circle()
                    .fill(VolioTheme.accent)
                    .frame(width: 10, height: 10)
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(width: 2)
            }
            .frame(width: 16)
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.title3.bold())
                        if !subtitle.isEmpty && subtitle != title {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(works.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(works) { work in
                        NavigationLink(value: work) {
                            TimelineTile(work: work)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
    }
}

private struct TimelineTile: View {
    var work: LocalWork

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    LocalThumbnail(path: work.thumbnailPath ?? work.originalPath, workId: work.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            if work.processingStatus != "ready", work.processingStatus != "succeeded" {
                Image(systemName: statusIcon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(.black.opacity(0.45), in: Circle())
                    .padding(5)
            }
        }
    }

    private var statusIcon: String {
        switch work.processingStatus {
        case "failed": "exclamationmark"
        case "waiting_for_mac": "desktopcomputer"
        default: "sparkles"
        }
    }
}
