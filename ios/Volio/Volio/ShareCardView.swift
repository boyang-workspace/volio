import SwiftUI
import UIKit

enum ShareCardTemplate: String, CaseIterable {
    case gallery
    case story

    var title: String {
        switch self {
        case .gallery: "Gallery"
        case .story: "Story"
        }
    }
}

private struct ShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ShareCardView: View {
    @Environment(VolioSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let work: LocalWork

    @State private var template: ShareCardTemplate = .gallery
    @State private var quote: String = ""
    @State private var isRendering = false
    @State private var shareImage: ShareImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Picker("Style", selection: $template) {
                        ForEach(ShareCardTemplate.allCases, id: \.self) { template in
                            Text(template.title).tag(template)
                        }
                    }
                    .pickerStyle(.segmented)

                    if template == .story {
                        TextField("Add their words...", text: $quote, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .lineLimit(2...4)
                            .padding(14)
                            .background(VolioTheme.card, in: RoundedRectangle(cornerRadius: 16))
                    }

                    cardPreview

                    Button {
                        renderShareCard()
                    } label: {
                        Label(isRendering ? "Preparing..." : "Share Card", systemImage: "square.and.arrow.up")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 16))
                    .tint(VolioTheme.accent)
                    .controlSize(.large)
                    .disabled(isRendering)
                }
                .padding(18)
            }
            .background(VolioTheme.paper.ignoresSafeArea())
            .navigationTitle("Share Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                quote = work.childQuote ?? ""
            }
            .sheet(item: $shareImage) { item in
                ActivityView(items: [item.image])
            }
        }
    }

    @ViewBuilder
    private var cardPreview: some View {
        if let image = originalImage {
            CardTemplateView(
                template: template,
                image: image,
                title: work.displayTitle,
                quote: template == .story ? (quote.isEmpty ? nil : quote) : nil,
                date: work.createdAroundLabel,
                age: work.timelineGroupTitle
            )
            .aspectRatio(4 / 5, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.14), radius: 18, y: 10)
        } else {
            ContentUnavailableView("Image not available", systemImage: "photo")
                .frame(maxWidth: .infinity, minHeight: 320)
                .background(VolioTheme.card, in: RoundedRectangle(cornerRadius: 24))
        }
    }

    private var originalImage: UIImage? {
        guard let path = work.originalPath,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return UIImage(data: data)
    }

    private func renderShareCard() {
        guard let image = originalImage else { return }
        isRendering = true
        let card = CardTemplateView(
            template: template,
            image: image,
            title: work.displayTitle,
            quote: template == .story ? (quote.isEmpty ? nil : quote) : nil,
            date: work.createdAroundLabel,
            age: work.timelineGroupTitle
        )
        .frame(width: 1080, height: 1350)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        renderer.proposedSize = .init(width: 1080, height: 1350)
        renderer.isOpaque = true

        if let image = renderer.uiImage {
            shareImage = ShareImage(image: image)
        }
        isRendering = false
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Card Template

struct CardTemplateView: View {
    let template: ShareCardTemplate
    let image: UIImage
    let title: String?
    let quote: String?
    let date: String
    let age: String?

    var body: some View {
        switch template {
        case .gallery:
            GalleryCard(image: image, title: title, date: date, age: age)
        case .story:
            StoryCard(image: image, quote: quote, date: date, age: age)
        }
    }
}

struct GalleryCard: View {
    let image: UIImage
    let title: String?
    let date: String
    let age: String?

    var body: some View {
        ZStack {
            VolioTheme.card

            VStack(spacing: 22) {
                HStack {
                    Text("VOLIO")
                        .font(.caption.weight(.black))
                        .tracking(3)
                    Spacer()
                    Text(date)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(VolioTheme.mutedInk)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 5)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title?.isEmpty == false ? title! : "Untitled")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(VolioTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    if let age, !age.isEmpty {
                        Text(age)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(VolioTheme.accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(44)
        }
    }
}

struct StoryCard: View {
    let image: UIImage
    let quote: String?
    let date: String
    let age: String?

    var body: some View {
        ZStack {
            VolioTheme.ink

            VStack(spacing: 24) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(14)
                    .background(VolioTheme.card, in: RoundedRectangle(cornerRadius: 12))
                    .rotationEffect(.degrees(-1.4))
                    .shadow(color: .black.opacity(0.24), radius: 14, y: 7)

                VStack(spacing: 12) {
                    Text(quote?.isEmpty == false ? quote! : "A small piece of the making.")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(VolioTheme.card)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.65)

                    HStack(spacing: 8) {
                        Text(date)
                        if let age, !age.isEmpty {
                            Text("/")
                            Text(age)
                        }
                    }
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(VolioTheme.ochre)
                }
            }
            .padding(44)
        }
    }
}
