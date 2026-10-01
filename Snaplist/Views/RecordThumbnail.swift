import ArchiveCore
import SwiftUI

/// A preview of a record's original: its first page, or the page a search
/// matched. Shows the category's symbol on its colour until the image is
/// ready, or if it can't be drawn.
struct RecordThumbnail: View {
    enum Style {
        /// A fixed square, for rows.
        case square(CGFloat)
        /// Fills the available width at 3:4, for grid cards.
        case card
    }

    @Environment(AppModel.self) private var model

    let record: Record
    var pagePosition: Int?
    var style: Style = .square(52)

    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(width: fixedSide, height: fixedSide)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    ZStack {
                        record.kind.tint.opacity(0.12)
                        Image(systemName: record.kind.symbol)
                            .font(isCard ? .largeTitle : .title3)
                            .foregroundStyle(record.kind.tint)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
            .animation(.easeOut(duration: 0.2), value: image != nil)
            .accessibilityHidden(true)
            .task(id: pagePosition) {
                image = await model.thumbnail(for: record.id, pagePosition: pagePosition, maxPixelSize: isCard ? 640 : 240)
            }
    }

    private var isCard: Bool {
        if case .card = style { return true }
        return false
    }

    private var fixedSide: CGFloat? {
        if case .square(let side) = style { return side }
        return nil
    }

    private var aspectRatio: CGFloat { isCard ? 3 / 4 : 1 }
    private var cornerRadius: CGFloat { isCard ? Theme.cardRadius : 8 }
}
