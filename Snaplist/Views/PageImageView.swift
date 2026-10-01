import ArchiveCore
import SwiftUI

/// One page of an original, with optional highlight boxes drawn over it.
struct PageImageView: View {
    let url: URL
    let type: AssetType
    let pageInAsset: Int
    var highlights: [PageRect] = []

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        // The overlay is exactly the fitted image, so 0...1 page
                        // coordinates scale straight onto it.
                        GeometryReader { geometry in
                            ForEach(Array(highlights.enumerated()), id: \.offset) { _, rect in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(.yellow.opacity(0.35))
                                    .frame(width: rect.width * geometry.size.width,
                                           height: rect.height * geometry.size.height)
                                    .position(x: (rect.x + rect.width / 2) * geometry.size.width,
                                              y: (rect.y + rect.height / 2) * geometry.size.height)
                            }
                        }
                    }
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(0.77, contentMode: .fit)
                    .overlay {
                        if failed {
                            Label("Can't show this page", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                        }
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .accessibilityLabel("Page \(pageInAsset + 1)")
        .task(id: url) {
            image = await PageImages.load(url, type: type, pageInAsset: pageInAsset, maxPixelSize: 1800)
            failed = image == nil
        }
    }
}
