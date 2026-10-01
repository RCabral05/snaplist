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

/// A page full screen: pinch or double-tap to zoom, swipe down or Done to close.
struct ZoomViewer: View {
    let url: URL
    let type: AssetType
    let pageInAsset: Int
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    ZoomableImage(image: image)
                        .ignoresSafeArea()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            // Full resolution here: the point is to read the fine print.
            image = await PageImages.load(url, type: type, pageInAsset: pageInAsset, maxPixelSize: 4000)
        }
    }
}

/// UIScrollView zooming, which SwiftUI doesn't offer for images on its own.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.delegate = context.coordinator

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Page image"
        scrollView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        /// Zooms to 3x around the tap, or back out.
        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > 1 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scrollView.bounds.width / 3, height: scrollView.bounds.height / 3)
                scrollView.zoom(to: CGRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2),
                                           size: size), animated: true)
            }
        }
    }
}
