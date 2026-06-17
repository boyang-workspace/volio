import SwiftUI

struct BatchRevealView: View {
    @Environment(VolioSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let childName: String
    let childAgeLabel: String?
    let workCount: Int
    let works: [Artwork]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    heroSection
                    collageSection
                    statsSection
                    actionsSection
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("\(workCount) works found their place.")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            VStack(spacing: 4) {
                Text(childName)
                    .font(.headline)
                if let age = childAgeLabel {
                    Text(age)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    private var collageSection: some View {
        let grid = works.prefix(12)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(grid) { work in
                if let urlStr = work.thumbnailAbsoluteURL ?? work.displayAbsoluteURL {
                    AsyncImage(url: URL(string: urlStr)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                                .frame(height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        default:
                            Rectangle().fill(.quaternary)
                                .frame(height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
    }

    private var statsSection: some View {
        let workTypes = Dictionary(grouping: works) { $0.workType ?? "unknown" }
        let themes = extractThemes()

        return VStack(alignment: .leading, spacing: 14) {
            if !workTypes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Types")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    FlowLayout(spacing: 8) {
                        ForEach(Array(workTypes.keys.sorted()), id: \.self) { type in
                            Text("\(type.capitalized) · \(workTypes[type]?.count ?? 0)")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.blue.opacity(0.1), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }

            if !themes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Themes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    FlowLayout(spacing: 8) {
                        ForEach(themes.prefix(6), id: \.self) { theme in
                            Text(theme)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.purple.opacity(0.1), in: Capsule())
                                .foregroundStyle(.purple)
                        }
                    }
                }
            }

            Text("\(workCount) works collected")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            NavigationLink {
                TimelineView()
            } label: {
                Label("Open the collection", systemImage: "clock")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            NavigationLink {
                EditionView()
            } label: {
                Label("Create an Edition", systemImage: "book")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func extractThemes() -> [String] {
        var themeCounts: [String: Int] = [:]
        for work in works {
            guard let tags = work.tags else { continue }
            for tag in tags where tag.type == "theme" {
                themeCounts[tag.name, default: 0] += 1
            }
        }
        return themeCounts
            .filter { $0.value > 1 }
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }
}

// MARK: - Simple Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var currentRowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                height += currentRowHeight + spacing
                currentX = 0
                currentRowHeight = 0
            }
            currentX += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
        height += currentRowHeight
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var currentX = bounds.minX
        var currentY = bounds.minY
        var currentRowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth + bounds.minX, currentX > bounds.minX {
                currentY += currentRowHeight + spacing
                currentX = bounds.minX
                currentRowHeight = 0
            }
            view.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
    }
}
