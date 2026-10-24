import SwiftUI

/// 추천 가구 카드. 이미지·브랜드 로고는 URL이 채워지면 표시된다.
struct ProductCardView: View {
    let product: Product
    let isSelected: Bool
    let onShare: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            remoteImage(product.imageURL)
                .frame(width: 159)
                .clipped()
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name)
                        Text(product.price)
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.black)
                    Spacer(minLength: 0)
                    Button(action: onShare) {
                        Image(systemName: "arrowshape.turn.up.right")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Color("GrayScale300"))
                    }
                    .accessibilityLabel("Share")
                }
                remoteImage(product.brandLogoURL, contentMode: .fit)
                    .frame(width: 65, height: 26, alignment: .leading)
                tagGrid
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .frame(height: 145)
        .background(Color("TuckSheet"))
        .clipShape(.rect(cornerRadius: 30))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 30)
                    .strokeBorder(Color("TuckBrown"), lineWidth: 3)
            }
        }
        .padding(.horizontal, 19)
    }

    private var tagGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                  spacing: 2) {
            ForEach(Array(product.tags.enumerated()), id: \.offset) { _, tag in
                Text(tag)
                    .font(.caption)
                    .foregroundStyle(Color("GrayScale300"))
                    .lineLimit(1)
            }
        }
    }

    private func remoteImage(_ url: URL?, contentMode: ContentMode = .fill) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            default:
                Rectangle().fill(Color("GrayScale100"))
            }
        }
    }
}

#Preview {
    VStack {
        ProductCardView(product: Product.samples[0], isSelected: true) {}
        ProductCardView(product: Product.samples[1], isSelected: false) {}
    }
}
