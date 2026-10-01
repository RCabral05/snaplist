import ArchiveCore
import SwiftUI

/// Possible duplicates on a record: a receipt or bill that also appears as a
/// line on a statement. Answers count such a purchase once; here the person
/// can confirm that, or say they're two purchases so both count.
struct DuplicatesSection: View {
    @Environment(AppModel.self) private var model
    let record: Record

    @State private var duplicates: [Duplicate] = []

    var body: some View {
        Group {
            if !duplicates.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(duplicates.count == 1 ? "Possible Duplicate" : "Possible Duplicates")
                            .font(Theme.display(.title3))
                        Text("\(duplicates.count)").foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    ForEach(duplicates) { pair in
                        DuplicateCard(duplicate: pair, viewedFrom: record.id) { isSame in
                            model.decide(pair, isSame: isSame)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .task(id: "\(record.id)-\(record.kind)-\(model.amountsRevision)") {
            duplicates = model.possibleDuplicates(involving: record.id)
        }
    }
}

/// One receipt-and-statement-line pair, with the choice to make about it.
struct DuplicateCard: View {
    let duplicate: Duplicate
    /// The record being looked at, so the card names the other one.
    var viewedFrom: UUID?
    var decide: (Bool?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline).font(.subheadline.weight(.semibold))
                    Text(explanation).font(.footnote).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 0) {
                side(duplicate.kept)
                Divider().padding(.leading)
                side(duplicate.dropped)
            }
            .background(Theme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))

            switch duplicate.decision {
            case nil:
                HStack(spacing: 10) {
                    Button("Same Purchase") { decide(true) }
                        .buttonStyle(.glassProminent)
                    Button("Different Purchases") { decide(false) }
                        .buttonStyle(.glass)
                }
                .font(.subheadline.weight(.semibold))
            case let decision?:
                Button(decision ? "Undo: They're Different" : "Undo: Count Once") { decide(nil) }
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private func side(_ item: Counted) -> some View {
        NavigationLink(value: RecordListView.Destination(record: item.record, pagePosition: item.transaction.pagePosition)) {
            HStack(spacing: 10) {
                RecordThumbnail(record: item.record, pagePosition: item.transaction.pagePosition, style: .square(34))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.record.title).font(.subheadline).lineLimit(1)
                    Text("\(item.transaction.source == .statement ? "Statement line" : item.record.kind.label) · \(item.day.date().formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(item.transaction.money.formatted).font(.subheadline.weight(.medium)).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.record.id == viewedFrom)
    }

    private var headline: String {
        switch duplicate.decision {
        case nil: "Is this the same purchase?"
        case true?: "Same purchase, counted once"
        case false?: "Different purchases, both counted"
        }
    }

    private var explanation: String {
        let money = duplicate.kept.transaction.money.formatted
        switch duplicate.decision {
        case nil:
            return "\(money) is on both a \(duplicate.kept.record.kind.label.lowercased()) and a statement within a few days. Until you say otherwise, answers count it once."
        case true?:
            return "You said these are the same \(money). Answers count the \(duplicate.kept.record.kind.label.lowercased()), not the statement line."
        case false?:
            return "You said these are two separate charges of \(money), so answers count both."
        }
    }

    private var icon: String {
        switch duplicate.decision {
        case nil: "questionmark.circle.fill"
        case true?: "checkmark.circle.fill"
        case false?: "plus.circle.fill"
        }
    }

    private var tint: Color {
        duplicate.decision == nil ? Theme.accent : .secondary
    }
}
