import ArchiveCore
import SwiftUI

/// A small square preview of a record's original: its first page, or the page
/// a search matched. Shows the category's symbol until the image is ready or
/// if it can't be drawn.
struct RecordThumbnail: View {
    @Environment(AppModel.self) private var model

    let record: Record
    var pagePosition: Int?
    var size: CGFloat = 52

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: record.kind.symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        .accessibilityHidden(true)
        .task(id: pagePosition) {
            image = await model.thumbnail(for: record.id, pagePosition: pagePosition)
        }
    }
}
