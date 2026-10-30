import SwiftUI

/// A buyable product; tapping opens the store's page. `store` adds the store name
/// next to the category, for lists that mix stores (search).
struct ProductCard: View {
    let product: Product
    var store: String? = nil
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = URL(string: product.productURL) { openURL(url) }
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ProductThumbnail(url: URL(string: product.imageURL))
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(product.name)
                        .font(Theme.body(Theme.Size.base, weight: .semibold))
                        .foregroundStyle(Theme.Palette.fg)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.body(Theme.Size.sm))
                            .foregroundStyle(Theme.Palette.fgMuted)
                            .lineLimit(1)
                    }
                    Text(product.formattedPrice)
                        .font(Theme.body(Theme.Size.md, weight: .bold))
                        .foregroundStyle(Theme.Palette.accent)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.Palette.sageInk))
            }
            .padding(12)
            .background(Theme.Palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Theme.Palette.fg.opacity(0.06), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the retailer's page")
    }

    /// "Fox Home · Sofa". Catalog slugs ("ceiling_lamp") read as code; show them as words.
    private var subtitle: String? {
        let category = product.category.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
        let parts = [store, category].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Product thumbnails from retailer CDNs.
///
/// Not `AsyncImage`: on the shared session, requests to cdn.shopify.com repeatedly
/// failed with -1005 / -1017 over a reused HTTP/3 connection and left every card
/// blank, while Safari on the same simulator loaded the same URL. An ephemeral
/// session keeps no connection or Alt-Svc state between thumbnails, and each load
/// is retried a few times before settling on the placeholder.
struct ProductThumbnail: View {
    let url: URL?
    @State private var image: UIImage?

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()

    var body: some View {
        ZStack {
            Theme.Palette.bgElevated
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .clipped()
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url, image == nil else { return }
        for attempt in 0..<4 {
            if Task.isCancelled { return }
            if let (data, response) = try? await Self.session.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let loaded = UIImage(data: data) {
                image = loaded
                return
            }
            try? await Task.sleep(for: .seconds(Double(attempt + 1)))
        }
    }
}
