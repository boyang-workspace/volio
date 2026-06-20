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
    @Environment(\.dismissVolioTransientOverlays) private var dismissTransientOverlays
    @State private var showSettings = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VolioPageHeader(title: "Gallery") {
                        headerActions
                    }

                    if session.works.isEmpty {
                        emptyState
                    } else {
                        MasonryGrid(
                            works: session.works,
                            onOpenWork: openWork
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 96)
            }
            .background(VolioTheme.paper.ignoresSafeArea())
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in dismissTransientOverlays() }
            )
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
            .onDisappear {
                dismissTransientOverlays()
            }
        }
    }

    private var headerActions: some View {
        HStack(spacing: 8) {
            Button {
                dismissTransientOverlays()
                showSettings = true
            } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .frame(width: 52, height: 52)
                    .volioGlass(cornerRadius: 26, interactive: true)
            }
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

    private func openWork(_ work: LocalWork) {
        dismissTransientOverlays()
        navigationPath.append(work)
    }
}

struct TimelineView: View {
    @Environment(VolioSession.self) private var session
    @Environment(\.dismissVolioTransientOverlays) private var dismissTransientOverlays
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSettings = false
    @State private var navigationPath = NavigationPath()
    @State private var surfaceEpoch = Int(Date().timeIntervalSince1970 / 86_400)
    @State private var surfacedIDs = Set<String>()
    @State private var placementContext: FloatingPlacementContext?
    @State private var stableFloatingAssignments: [String: [FloatingWorkAssignment]] = [:]
    @State private var undoPlacement: PlacementUndoState?

    private var sections: [TimelineSectionModel] {
        TimelineGroupingService.sections(for: session.works)
    }

    private var displaySections: [TimelineSectionModel] {
        if !sections.isEmpty {
            return sections
        }
        guard !unplacedWorksForSurfacing.isEmpty else {
            return []
        }
        return [
            TimelineSectionModel(
                id: "unplaced-prompts",
                title: "Recently saved",
                subtitle: "Waiting for a remembered time",
                sortKey: Date().timeIntervalSince1970,
                placementInput: .unknown,
                works: []
            )
        ]
    }

    private var unplacedWorksForSurfacing: [LocalWork] {
        TimelineGroupingService.unplacedWorks(from: session.works)
    }

    private var assignmentContextKey: String {
        [
            String(surfaceEpoch),
            displaySections.map(\.id).joined(separator: "|"),
            unplacedWorksForSurfacing.map(\.id).sorted().joined(separator: "|")
        ].joined(separator: "::")
    }

    private var activeFloatingAssignments: [String: [FloatingWorkAssignment]] {
        stableFloatingAssignments
    }

    private var activeFloatingWorkIDs: [String] {
        activeFloatingAssignments.flatMap { $0.value.map(\.work.id) }.sorted()
    }

    private var hasAnyWorks: Bool {
        !session.works.isEmpty
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    VolioPageHeader(title: "Timeline") {
                        headerActions
                    }
                    .padding(.horizontal, 18)

                    if !hasAnyWorks {
                        ContentUnavailableView("No timeline yet", systemImage: "clock", description: Text("Capture or sync works to build a creative timeline."))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 120)
                    } else if displaySections.isEmpty {
                        ContentUnavailableView(
                            "No remembered times yet",
                            systemImage: "sparkles",
                            description: Text("Works are saved. Volio will gently resurface the ones whose time you have not remembered yet.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                    } else {
                        ForEach(displaySections) { section in
                            TimelineAgeSection(
                                title: section.title,
                                subtitle: section.subtitle,
                                works: section.works,
                                floatingItems: activeFloatingAssignments[section.id] ?? [],
                                onOpenWork: openWork
                            ) { assignment in
                                placementContext = FloatingPlacementContext(work: assignment.work, section: section)
                            }
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 96)
            }
            .background(VolioTheme.paper.ignoresSafeArea())
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in dismissTransientOverlays() }
            )
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await session.refreshLibrary(showError: true)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsContent() }
            }
            .sheet(item: $placementContext) { context in
                PlaceArtworkSheet(
                    context: context,
                    earlierSection: adjacentSection(from: context.section, direction: .earlier),
                    laterSection: adjacentSection(from: context.section, direction: .later),
                    onPlace: { work, section in
                        place(work, in: section)
                    },
                    onChooseTime: { work, input in
                        place(work, using: input)
                    },
                    onMove: { section in
                        placementContext = FloatingPlacementContext(work: context.work, section: section)
                    },
                    onSnooze: { work in
                        snooze(work)
                    }
                )
                .environment(session)
            }
            .navigationDestination(for: LocalWork.self) { work in
                ArtworkDetailView(work: work)
            }
            .overlay(alignment: .bottom) {
                if let undoPlacement {
                    PlacementUndoToast(
                        state: undoPlacement,
                        onUndo: undoLastPlacement
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 104)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onDisappear {
                dismissTransientOverlays()
            }
            .onAppear {
                rebuildFloatingAssignmentsIfNeeded()
            }
            .onChange(of: assignmentContextKey) { _, _ in
                rebuildFloatingAssignmentsIfNeeded()
            }
            .task(id: activeFloatingWorkIDs.joined(separator: ",")) {
                let ids = Set(activeFloatingWorkIDs)
                let newIDs = ids.subtracting(surfacedIDs)
                guard !newIDs.isEmpty else { return }
                surfacedIDs.formUnion(newIDs)
                session.markWorksSurfaced(Array(newIDs))
            }
        }
    }

    private var headerActions: some View {
        HStack(spacing: 8) {
            Button {
                dismissTransientOverlays()
                showSettings = true
            } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .frame(width: 52, height: 52)
                    .volioGlass(cornerRadius: 26, interactive: true)
            }
            .buttonStyle(.plain)
        }
    }

    private func openWork(_ work: LocalWork) {
        dismissTransientOverlays()
        navigationPath.append(work)
    }

    private func rebuildFloatingAssignmentsIfNeeded() {
        stableFloatingAssignments = FloatingArtworkSurfacingService.assignments(
            sections: displaySections,
            unplacedWorks: unplacedWorksForSurfacing,
            surfaceEpoch: surfaceEpoch
        )
    }

    private func place(_ work: LocalWork, in section: TimelineSectionModel) {
        place(work, using: section.placementInput, sectionTitle: section.title)
    }

    private func place(_ work: LocalWork, using input: CreatedAroundInput, sectionTitle: String? = nil) {
        let snapshot = CreationTimeSnapshot(work: work)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.86)) {
            session.updateCreationTime(work, createdAround: input)
            placementContext = nil
            undoPlacement = PlacementUndoState(
                workID: work.id,
                snapshot: snapshot,
                message: "Placed in \"\(sectionTitle ?? work.createdAroundLabel)\""
            )
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if undoPlacement?.workID == work.id {
                withAnimation(.easeOut(duration: 0.18)) {
                    undoPlacement = nil
                }
            }
        }
    }

    private func snooze(_ work: LocalWork) {
        session.snoozeUnplacedWork(work)
        surfacedIDs.insert(work.id)
        placementContext = nil
        rebuildFloatingAssignmentsIfNeeded()
    }

    private func undoLastPlacement() {
        guard let undoPlacement,
              let work = session.works.first(where: { $0.id == undoPlacement.workID })
        else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.36, dampingFraction: 0.9)) {
            session.restoreCreationTime(work, snapshot: undoPlacement.snapshot)
            self.undoPlacement = nil
            rebuildFloatingAssignmentsIfNeeded()
        }
    }

    private enum TimelineDirection {
        case earlier
        case later
    }

    private func adjacentSection(from section: TimelineSectionModel, direction: TimelineDirection) -> TimelineSectionModel? {
        guard let index = sections.firstIndex(where: { $0.id == section.id }) else { return nil }
        switch direction {
        case .earlier:
            let next = index + 1
            return sections.indices.contains(next) ? sections[next] : nil
        case .later:
            let previous = index - 1
            return sections.indices.contains(previous) ? sections[previous] : nil
        }
    }
}

struct TimelineSectionModel: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var sortKey: Double
    var placementInput: CreatedAroundInput
    var works: [LocalWork]
}

enum TimelineGroupingService {
    static func sections(for works: [LocalWork]) -> [TimelineSectionModel] {
        let placed = works.filter { !$0.isTimeUnplaced }
        let grouped = Dictionary(grouping: placed) { work in
            sectionID(for: work)
        }
        return grouped.map { id, works in
            let sorted = works.sorted { sortKey(for: $0) > sortKey(for: $1) }
            let title = sorted.first?.timelineGroupTitle ?? id
            let subtitle = subtitle(for: sorted)
            return TimelineSectionModel(
                id: id,
                title: title,
                subtitle: subtitle,
                sortKey: sorted.map(sortKey(for:)).max() ?? 0,
                placementInput: placementInput(for: sorted.first),
                works: sorted
            )
        }
        .sorted { left, right in
            left.sortKey > right.sortKey
        }
    }

    static func unplacedWorks(from works: [LocalWork]) -> [LocalWork] {
        works
            .filter { work in
                let canSurface = work.snoozedUntil.map { $0 <= Date() } ?? true
                return canSurface && work.isTimeUnplaced && (ImageStorage.hasThumbnail(id: work.id) || ImageStorage.hasOriginal(id: work.id))
            }
            .sorted { left, right in
                if left.surfaceCount != right.surfaceCount {
                    return left.surfaceCount < right.surfaceCount
                }
                return (left.lastSurfacedAt ?? .distantPast) < (right.lastSurfacedAt ?? .distantPast)
            }
    }

    static func sectionID(for work: LocalWork) -> String {
        if let lifeStageID = work.lifeStageID, !lifeStageID.isEmpty {
            return "life:\(lifeStageID)"
        }
        if let start = work.creationAgeStartMonths {
            if let end = work.creationAgeEndMonths, end != start {
                return "age_range:\(start)-\(end)"
            }
            return "age:\(start / 12)"
        }
        if let months = work.createdAroundAgeMonths ?? work.ageAtCreationMonths {
            return "age:\(months / 12)"
        }
        if work.creationTimeKind == .season,
           let year = work.creationYear ?? work.createdAroundYear,
           let season = work.creationSeasonRaw ?? work.createdAroundSeason {
            return "season:\(year):\(season)"
        }
        if let year = work.creationYear ?? work.createdAroundYear {
            return "year:\(year)"
        }
        return "captured:\(Calendar.current.component(.year, from: work.capturedAt))"
    }

    static func sortKey(for work: LocalWork) -> Double {
        work.timelineSortKey ?? LocalWork.sortKey(
            dateStart: work.creationDateStart,
            dateEnd: work.creationDateEnd,
            ageStartMonths: work.creationAgeStartMonths ?? work.createdAroundAgeMonths ?? work.ageAtCreationMonths,
            ageEndMonths: work.creationAgeEndMonths,
            year: work.creationYear ?? work.createdAroundYear,
            month: work.creationMonth ?? work.createdAroundMonth,
            capturedAt: work.capturedAt,
            placement: work.timelinePlacementState
        ) ?? work.capturedAt.timeIntervalSince1970
    }

    private static func subtitle(for works: [LocalWork]) -> String {
        let labels = Array(NSOrderedSet(array: works.map(\.createdAroundLabel))).compactMap { $0 as? String }
        guard let first = labels.first else { return "" }
        return labels.count == 1 ? first : "\(works.count) works"
    }

    static func placementInput(for work: LocalWork?) -> CreatedAroundInput {
        guard let work else { return .unknown }
        switch work.creationTimeKind {
        case .exactDate:
            if let date = work.creationDateStart { return .exactDate(date) }
        case .yearMonth:
            if let year = work.creationYear ?? work.createdAroundYear,
               let month = work.creationMonth ?? work.createdAroundMonth {
                return .yearMonth(year, month)
            }
        case .season:
            if let season = work.creationSeasonRaw ?? work.createdAroundSeason,
               let year = work.creationYear ?? work.createdAroundYear {
                return .season(season, year)
            }
        case .year:
            if let year = work.creationYear ?? work.createdAroundYear {
                return .year(year)
            }
        case .age:
            if let months = work.creationAgeStartMonths ?? work.createdAroundAgeMonths ?? work.ageAtCreationMonths {
                return .ageYears(max(0, months) / 12)
            }
        case .ageRange:
            if let start = work.creationAgeStartMonths,
               let end = work.creationAgeEndMonths {
                return .ageRange(max(0, start) / 12, max(0, end) / 12)
            }
        case .lifeStage:
            if let id = work.lifeStageID {
                return .lifeStage(id, work.customTimeLabel ?? work.timelineGroupTitle)
            }
        case .capturedDate:
            return .capturedDate
        case .relative, .unknown:
            break
        }
        return .unknown
    }
}

struct MasonryGrid: View {
    var works: [LocalWork]
    var onOpenWork: (LocalWork) -> Void = { _ in }

    private var sortedWorks: [LocalWork] {
        works.sorted { $0.capturedAt > $1.capturedAt }
    }

    var body: some View {
        RowMasonryLayout(columns: 2, spacing: 10) {
            ForEach(sortedWorks) { work in
                MasonryTile(work: work)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture {
                        onOpenWork(work)
                    }
            }
        }
    }
}

struct MasonryTile: View {
    var work: LocalWork
    @State private var displayAspectRatio: CGFloat

    init(work: LocalWork) {
        self.work = work
        _displayAspectRatio = State(initialValue: work.imageAspectRatio)
    }

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

    var body: some View {
        CachedArtworkImage(
            workID: workId,
            thumbnailPath: primaryPath,
            originalPath: fallbackPath ?? inferredOriginalPath(from: primaryPath),
            targetSize: CGSize(width: 260, height: 340),
            aspectRatio: displayAspectRatio,
            onMetadata: { metadata in
                guard let ratio = metadata.aspectRatio else { return }
                displayAspectRatio = min(max(ratio, 0.55), 1.65)
            }
        )
            .aspectRatio(displayAspectRatio, contentMode: .fill)
            .clipped()
    }

    private func inferredOriginalPath(from path: String?) -> String? {
        guard let path, path.hasSuffix("thumbnail.jpg") else { return nil }
        return URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("original.jpg").path
    }
}

private struct RowMasonryLayout: Layout {
    var columns: Int = 2
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        guard width > 0, !subviews.isEmpty else { return CGSize(width: width, height: 0) }

        let columnCount = max(1, columns)
        let columnWidth = (width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        var totalHeight: CGFloat = 0

        var rowStart = 0
        while rowStart < subviews.count {
            let rowEnd = min(rowStart + columnCount, subviews.count)
            var rowHeight: CGFloat = 0
            for i in rowStart..<rowEnd {
                let size = subviews[i].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
                rowHeight = max(rowHeight, size.height)
            }
            if rowStart > 0 { totalHeight += spacing }
            totalHeight += rowHeight
            rowStart = rowEnd
        }

        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard bounds.width > 0 else { return }

        let columnCount = max(1, columns)
        let columnWidth = (bounds.width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        var currentY = bounds.minY

        var rowStart = 0
        while rowStart < subviews.count {
            let rowEnd = min(rowStart + columnCount, subviews.count)

            var rowHeight: CGFloat = 0
            for i in rowStart..<rowEnd {
                let size = subviews[i].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
                rowHeight = max(rowHeight, size.height)
            }

            for (offset, i) in (rowStart..<rowEnd).enumerated() {
                let x = bounds.minX + CGFloat(offset) * (columnWidth + spacing)
                let size = subviews[i].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
                subviews[i].place(
                    at: CGPoint(x: x, y: currentY),
                    proposal: ProposedViewSize(width: columnWidth, height: size.height)
                )
            }

            currentY += rowHeight + spacing
            rowStart = rowEnd
        }
    }
}

struct SearchView: View {
    @Environment(VolioSession.self) private var session
    @Environment(\.dismissVolioTransientOverlays) private var dismissTransientOverlays
    @State private var query = ""
    @State private var semanticEnabled = true
    @FocusState private var searchFocused: Bool

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
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        dismissTransientOverlays()
                        searchFocused = false
                    }
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LocalWork.self) { work in
                ArtworkDetailView(work: work)
            }
            .onDisappear {
                dismissSearchChrome()
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
                .focused($searchFocused)
                .onChange(of: searchFocused) { _, isFocused in
                    if isFocused {
                        dismissTransientOverlays()
                    }
                }
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
                Label("Smart Search", systemImage: "sparkle.magnifyingglass")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(VolioTheme.ink)
                Spacer()
                Toggle("", isOn: $semanticEnabled)
                    .labelsHidden()
                    .tint(VolioTheme.accent)
            }
            Text("Search across AI descriptions, tags, materials, colors, ages, and notes. A deeper Mac index can plug into this page later.")
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
        .contentShape(Rectangle())
        .onTapGesture {
            dismissSearchChrome()
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
                            dismissSearchChrome()
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
        .contentShape(Rectangle())
        .onTapGesture {
            dismissSearchChrome()
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
        .contentShape(Rectangle())
        .onTapGesture {
            dismissSearchChrome()
        }
    }

    private func quickQuery(_ value: String) -> some View {
        Button {
            query = value
            dismissSearchChrome()
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

    private func dismissSearchChrome() {
        searchFocused = false
        dismissTransientOverlays()
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var title: String
    var subtitle: String
    var works: [LocalWork]
    var floatingItems: [FloatingWorkAssignment] = []
    var onOpenWork: (LocalWork) -> Void = { _ in }
    var onOpenFloatingWork: (FloatingWorkAssignment) -> Void = { _ in }

    private let columns = [GridItem(.adaptive(minimum: 86), spacing: 8)]
    private var useInlineFloating: Bool { dynamicTypeSize.isAccessibilitySize }
    private var minimumSectionHeight: CGFloat? {
        works.isEmpty && !floatingItems.isEmpty ? 420 : nil
    }

    var body: some View {
        sectionContent
            .frame(minHeight: minimumSectionHeight, alignment: .top)
            .padding(.horizontal, 18)
            .overlay {
                if !useInlineFloating {
                    FloatingWorksOverlay(
                        items: floatingItems,
                        sectionTitle: title,
                        onOpen: onOpenFloatingWork
                    )
                }
            }
    }

    private var sectionContent: some View {
        HStack(alignment: .top, spacing: 12) {
            timelineRail

            VStack(alignment: .leading, spacing: 10) {
                sectionHeader

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(works) { work in
                        TimelineTile(work: work)
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                            .onTapGesture {
                                onOpenWork(work)
                        }
                    }
                }

                if useInlineFloating && !floatingItems.isEmpty {
                    FloatingMemoryStrip(
                        items: floatingItems,
                        sectionTitle: title,
                        onOpen: onOpenFloatingWork
                    )
                }
            }
        }
    }

    private var timelineRail: some View {
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
    }

    private var sectionHeader: some View {
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
    }
}

struct FloatingPlacementContext: Identifiable {
    var work: LocalWork
    var section: TimelineSectionModel
    var id: String { "\(work.id)::\(section.id)" }
}

struct PlacementUndoState: Identifiable {
    var id: String { workID }
    var workID: String
    var snapshot: CreationTimeSnapshot
    var message: String
}

enum FloatingSide {
    case left
    case right
}

struct FloatingWorkAssignment: Identifiable {
    var id: String { "\(work.id)::\(sectionID)" }
    var work: LocalWork
    var sectionID: String
    var side: FloatingSide
    var rotation: Double
    var verticalFraction: CGFloat
    var horizontalInset: CGFloat
    var size: CGFloat
    var scale: CGFloat
    var opacity: Double
}

enum FloatingArtworkSurfacingService {
    static func assignments(
        sections: [TimelineSectionModel],
        unplacedWorks: [LocalWork],
        surfaceEpoch: Int
    ) -> [String: [FloatingWorkAssignment]] {
        guard !sections.isEmpty, !unplacedWorks.isEmpty else { return [:] }

        let candidates = unplacedWorks
            .sorted { left, right in
                if left.surfaceCount != right.surfaceCount {
                    return left.surfaceCount < right.surfaceCount
                }
                let leftSeed = combinedSeed(workSeed: left.displaySeed, sectionID: "candidate", epoch: surfaceEpoch)
                let rightSeed = combinedSeed(workSeed: right.displaySeed, sectionID: "candidate", epoch: surfaceEpoch)
                return leftSeed < rightSeed
            }
            .prefix(min(6, unplacedWorks.count))

        var assignments: [String: [FloatingWorkAssignment]] = [:]
        var candidateIndex = candidates.startIndex
        for section in sections where candidateIndex < candidates.endIndex {
            var sectionItems: [FloatingWorkAssignment] = []
            for side in [FloatingSide.left, .right] where candidateIndex < candidates.endIndex {
                let work = candidates[candidateIndex]
                sectionItems.append(makeAssignment(work: work, section: section, side: side, epoch: surfaceEpoch))
                candidateIndex = candidates.index(after: candidateIndex)
            }
            if !sectionItems.isEmpty {
                assignments[section.id] = sectionItems
            }
        }
        return assignments
    }

    private static func makeAssignment(
        work: LocalWork,
        section: TimelineSectionModel,
        side: FloatingSide,
        epoch: Int
    ) -> FloatingWorkAssignment {
        let seed = combinedSeed(workSeed: work.displaySeed, sectionID: section.id, epoch: epoch)
        return FloatingWorkAssignment(
            work: work,
            sectionID: section.id,
            side: side,
            rotation: value(seed: seed, salt: 3, range: -4...4),
            verticalFraction: CGFloat(value(seed: seed, salt: 7, range: 0.34...0.82)),
            horizontalInset: CGFloat(value(seed: seed, salt: 11, range: -10...12)),
            size: CGFloat(value(seed: seed, salt: 13, range: 78...112)),
            scale: CGFloat(value(seed: seed, salt: 17, range: 0.94...1.04)),
            opacity: value(seed: seed, salt: 19, range: 0.90...1.0)
        )
    }

    private static func combinedSeed(workSeed: Int64, sectionID: String, epoch: Int) -> UInt64 {
        var hash = UInt64(bitPattern: workSeed)
        hash ^= UInt64(epoch &* 16_777_619)
        for byte in sectionID.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash == 0 ? 1 : hash
    }

    private static func value(seed: UInt64, salt: UInt64, range: ClosedRange<Double>) -> Double {
        var mixed = seed ^ (salt &* 0x9E37_79B9_7F4A_7C15)
        mixed ^= mixed >> 30
        mixed &*= 0xBF58_476D_1CE4_E5B9
        mixed ^= mixed >> 27
        mixed &*= 0x94D0_49BB_1331_11EB
        mixed ^= mixed >> 31
        let unit = Double(mixed % 10_000) / 10_000
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}

private struct FloatingWorksOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var items: [FloatingWorkAssignment]
    var sectionTitle: String
    var onOpen: (FloatingWorkAssignment) -> Void

    var body: some View {
        GeometryReader { proxy in
            ForEach(items) { item in
                FloatingArtworkCard(
                    assignment: item,
                    sectionTitle: sectionTitle,
                    onOpen: onOpen
                )
                .position(position(for: item, in: proxy.size))
            }
        }
        .allowsHitTesting(!items.isEmpty)
        .visualEffect { content, proxy in
            guard !reduceMotion else { return content.offset(y: 0) }
            let minY = proxy.frame(in: .scrollView).minY
            let parallax = min(max(minY * -0.075, -28), 28)
            return content.offset(y: parallax)
        }
    }

    private func position(for item: FloatingWorkAssignment, in size: CGSize) -> CGPoint {
        let x: CGFloat
        switch item.side {
        case .left:
            x = max(22, item.size * 0.34 + item.horizontalInset)
        case .right:
            x = min(size.width - 22, size.width - item.size * 0.34 - item.horizontalInset)
        }
        let y = min(max(72, size.height * item.verticalFraction), max(72, size.height - 34))
        return CGPoint(x: x, y: y)
    }
}

private struct FloatingMemoryStrip: View {
    var items: [FloatingWorkAssignment]
    var sectionTitle: String
    var onOpen: (FloatingWorkAssignment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Some works are still finding their time")
                .font(.caption.weight(.semibold))
                .foregroundStyle(VolioTheme.mutedInk)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        FloatingArtworkCard(
                            assignment: item,
                            sectionTitle: sectionTitle,
                            onOpen: onOpen,
                            compact: true
                        )
                    }
                }
            }
        }
        .padding(.top, 6)
    }
}

private struct FloatingArtworkCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var assignment: FloatingWorkAssignment
    var sectionTitle: String
    var onOpen: (FloatingWorkAssignment) -> Void
    var compact = false

    private var cardHeight: CGFloat {
        compact ? 62 : assignment.size
    }

    private var cardWidth: CGFloat {
        compact ? 62 : assignment.size * min(max(assignment.work.imageAspectRatio, 0.72), 1.45)
    }

    var body: some View {
        Button {
            onOpen(assignment)
        } label: {
            LocalThumbnail(
                path: assignment.work.thumbnailPath ?? assignment.work.originalPath,
                workId: assignment.work.id,
                targetSize: CGSize(width: cardWidth * 2.4, height: cardHeight * 2.4)
            )
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.78), lineWidth: 1.5)
                }
                .shadow(color: .black.opacity(0.18), radius: 8, y: 5)
        }
        .buttonStyle(.plain)
        .frame(width: cardWidth, height: cardHeight)
        .scaleEffect(compact ? 1 : assignment.scale)
        .rotationEffect(.degrees(compact ? 0 : assignment.rotation))
        .opacity(compact ? 1 : assignment.opacity)
        .visualEffect { content, proxy in
            guard !compact, !reduceMotion else { return content.offset(y: 0) }
            let minY = proxy.frame(in: .scrollView).minY
            return content.offset(y: min(max(minY * -0.018, -8), 8))
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to try placing it near \(sectionTitle).")
    }

    private var accessibilityLabel: String {
        let title = assignment.work.displayTitle
        return "Work without a remembered time, \(title)."
    }
}

private struct PlaceArtworkSheet: View {
    @Environment(\.dismiss) private var dismiss
    var context: FloatingPlacementContext
    var earlierSection: TimelineSectionModel?
    var laterSection: TimelineSectionModel?
    var onPlace: (LocalWork, TimelineSectionModel) -> Void
    var onChooseTime: (LocalWork, CreatedAroundInput) -> Void
    var onMove: (TimelineSectionModel) -> Void
    var onSnooze: (LocalWork) -> Void
    @State private var showCustomTime = false
    @State private var draft = CreationTimeDraft(mode: .unknown)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    preview
                    primaryActions
                    if showCustomTime {
                        CreationTimePicker(title: "Choose another time", draft: $draft)
                        Button {
                            onChooseTime(context.work, draft.input)
                        } label: {
                            Label("Place with this time", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(VolioTheme.accent)
                        .controlSize(.large)
                    }
                }
                .padding(18)
            }
            .background(VolioTheme.paper.ignoresSafeArea())
            .navigationTitle("Remember Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Remember when this was made?")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(VolioTheme.ink)
            Text("It appeared near \(context.section.title). That is only a memory prompt, not an AI guess.")
                .font(.subheadline)
                .foregroundStyle(VolioTheme.mutedInk)
        }
    }

    private var preview: some View {
        LocalThumbnail(
            path: context.work.thumbnailPath ?? context.work.originalPath,
            workId: context.work.id,
            targetSize: CGSize(width: 680, height: 520)
        )
            .aspectRatio(context.work.imageAspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(alignment: .bottomLeading) {
                Text(context.work.displayTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .shadow(radius: 4)
            }
    }

    private var primaryActions: some View {
        VStack(spacing: 10) {
            Button {
                onPlace(context.work, context.section)
            } label: {
                Label("This time feels right", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(VolioTheme.accent)
            .controlSize(.large)

            HStack(spacing: 10) {
                Button {
                    if let earlierSection {
                        onMove(earlierSection)
                    }
                } label: {
                    Label("Earlier", systemImage: "arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .disabled(earlierSection == nil)

                Button {
                    if let laterSection {
                        onMove(laterSection)
                    }
                } label: {
                    Label("Later", systemImage: "arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .disabled(laterSection == nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    showCustomTime.toggle()
                }
            } label: {
                Label("Choose another time", systemImage: "calendar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                onSnooze(context.work)
            } label: {
                Text("Not remembered yet")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(VolioTheme.mutedInk)
            .padding(.top, 4)
        }
    }
}

private struct PlacementUndoToast: View {
    var state: PlacementUndoState
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(state.message)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Spacer()
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(VolioTheme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(Color.white.opacity(0.55), lineWidth: 1)
        }
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
