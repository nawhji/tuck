import SwiftUI

/// Recommended furniture card. The favorite button overlays the image at top right, and the link button at bottom right.
/// The bottom-left button toggles Try/Remove. The link button opens the product page (`source_url`).
struct ProductCardView: View {
    let product: Product
    let isSelected: Bool
    var onToggle: (() -> Void)? = nil
    @Environment(FavoritesStore.self) private var favorites
    private var isLiked: Bool { favorites.contains(product.id) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(product.price)
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.black)
                Text(product.brand)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color("TuckBrown"))
                    .lineLimit(1)
                keywordGrid
                Spacer(minLength: 0)
                if let onToggle { tryButton(onToggle) }
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            RemoteImage(url: product.imageURL)
                .frame(width: 170)
                .overlay(alignment: .topTrailing) { likeButton }
                .overlay(alignment: .bottomTrailing) { linkButton }
        }
        .frame(height: 218)
        .background(.white)
        .clipShape(.rect(cornerRadius: 30))
        .padding(.horizontal, 19)
    }

    private func tryButton(_ onToggle: @escaping () -> Void) -> some View {
        Button(action: onToggle) {
            Text(isSelected ? "Remove" : "Try")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background(isSelected ? Color("GrayScale300") : Color("TuckBrown"), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private var likeButton: some View {
        Button { favorites.toggle(product) } label: {
            Image(systemName: isLiked ? "heart.fill" : "heart")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(isLiked ? .red : Color("GrayScale300"))
                .padding(12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLiked ? "Unlike" : "Like")
    }

    @ViewBuilder
    private var linkButton: some View {
        if let url = product.sourceURL {
            Link(destination: url) {
                Image(systemName: "arrowshape.turn.up.right")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color("GrayScale300"))
                    .padding(12)
            }
            .accessibilityLabel("Open product page")
        }
    }

    private var keywordGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                  spacing: 2) {
            ForEach(Array(product.keywords.enumerated()), id: \.offset) { _, keyword in
                Text("#\(keyword)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color("GrayScale300"))
                    .lineLimit(1)
            }
        }
    }
}

/// Remote image fitted to its container without changing its aspect ratio.
/// In a `LazyVStack`, `AsyncImage` can remain in a failed state after a request is cancelled when a view is rebuilt.
/// This loader retries cancelled requests and caches images after the first successful load.
struct RemoteImage: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
        }
        .task(id: url) { image = await ImageLoader.shared.image(for: url) }
    }
}

final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()
    private let cache = NSCache<NSURL, UIImage>()

    func image(for url: URL?, attempts: Int = 3) async -> UIImage? {
        guard let url else { return nil }
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        for attempt in 0..<attempts {
            if let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) {
                cache.setObject(image, forKey: url as NSURL)
                return image
            }
            if Task.isCancelled { return nil }
            try? await Task.sleep(for: .seconds(Double(attempt + 1) * 0.5))
        }
        return nil
    }
}

#Preview {
    VStack {
        ProductCardView(product: Product.samples[0], isSelected: true, onToggle: {})
        ProductCardView(product: Product.samples[1], isSelected: false, onToggle: {})
    }
    .environment(FavoritesStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("tuck-preview-favorites.json")))
}
