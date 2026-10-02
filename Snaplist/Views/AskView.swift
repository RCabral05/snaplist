import ArchiveCore
import SwiftUI

/// Questions about the archive, answered from what's saved in it. Totals are
/// added up by code from stored amounts; every answer lists the records it
/// used; and when the archive doesn't have the answer, it says so.
struct AskView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var question: String
    @State private var answer: AskResult?
    @State private var isAnswering = false
    @FocusState private var isFocused: Bool

    /// False when Ask is a tab rather than a sheet.
    var showsDone = true

    /// Starts with `question` asked, e.g. one handed over by Siri.
    init(question: String = "", showsDone: Bool = true) {
        _question = State(initialValue: question)
        self.showsDone = showsDone
    }

    static let examples = [
        "How much did I spend on gas last month?",
        "What was my electric bill in August?",
        "Where did I put the spare HDMI cable?",
        "When does the warranty on my TV expire?",
        "How much have I spent at Costco this year?",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    questionField
                    if isAnswering {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
                    } else if let answer {
                        AnswerView(result: answer, reask: { query in
                            self.answer = model.answer(query)
                        }, decided: {
                            // The same question, period and all, with the decision applied.
                            if case .spending(let shown) = self.answer { self.answer = model.answer(shown.query) }
                        })
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        examples
                    }
                }
                .padding()
                .animation(.snappy, value: answer?.id)
            }
            .background(Theme.background)
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(showsDone ? .inline : .large)
            .navigationDestination(for: RecordListView.Destination.self) { destination in
                RecordDetailView(record: destination.record, focusPage: destination.pagePosition)
            }
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .onAppear {
                if !question.isEmpty, answer == nil { ask() } else if showsDone { isFocused = true }
            }
        }
    }

    private var questionField: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass").foregroundStyle(Theme.accent)
            TextField("Ask about your receipts, bills and things", text: $question, axis: .vertical)
                .lineLimit(1...3)
                .submitLabel(.search)
                .focused($isFocused)
                .onSubmit(ask)
                .accessibilityIdentifier("ask-field")
            if !question.isEmpty {
                Button("Ask", action: ask)
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("ask-button")
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Self.examples, id: \.self) { example in
                Button {
                    question = example
                    ask()
                } label: {
                    Text(example)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            Label("Answers come only from what you've saved, worked out on this iPhone.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
    }

    private func ask() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isFocused = false
        Task {
            // Rules answer at once; a spinner only if Apple Intelligence is reading it.
            let slow = Task { try await Task.sleep(for: .milliseconds(150)); isAnswering = true }
            let result = await model.ask(text)
            slow.cancel()
            isAnswering = false
            answer = result
        }
    }
}

/// What a question came back with.
enum AskResult {
    case spending(SpendingAnswer)
    case whereIs([SearchHit], terms: [String])
    case expiry([ExpiryFinding], terms: [String])
    case search([SearchHit], text: String)
    /// Records tagged with the people and places a question named.
    case records(TaggedRecords)
    /// Receipt lines naming something, newest first.
    case lastBought([Counted], terms: [String])
    /// A saved thing: when it was bought, its warranty, its paperwork.
    case thing(ThingAnswer)
    /// What something has cost over time.
    case priceHistory(PriceHistory?, terms: [String])
    /// Everything in a collection.
    case collection(Collection, [Record])

    /// Changes whenever the answer does, for animation.
    var id: String {
        switch self {
        case .spending(let a): "s\(a.counted.count)\(a.totals.map(\.cents))\(a.query.rangeLabel ?? "")"
        case .whereIs(let hits, let terms): "w\(hits.map(\.id))\(terms)"
        case .expiry(let found, let terms): "e\(found.map(\.day))\(terms)"
        case .search(let hits, let text): "q\(hits.map(\.id))\(text)"
        case .records(let tagged): "r\(tagged.records.map(\.id))"
        case .lastBought(let found, let terms): "l\(found.map(\.id))\(terms)"
        case .thing(let answer): "t\(answer.profiles.map(\.id))\(answer.topic)"
        case .priceHistory(let history, let terms): "p\(history?.points.map(\.id) ?? [])\(terms)"
        case .collection(let collection, let records): "c\(collection.id)\(records.count)"
        }
    }
}

struct AnswerView: View {
    let result: AskResult
    /// Re-asks a spending question for another period.
    var reask: (SpendingQuery) -> Void
    /// Asks again after a duplicate was decided, since the total changes.
    var decided: () -> Void

    var body: some View {
        switch result {
        case .spending(let answer): SpendingAnswerView(answer: answer, reask: reask, decided: decided)
        case .whereIs(let hits, let terms): WhereAnswerView(hits: hits, terms: terms)
        case .expiry(let found, let terms): ExpiryAnswerView(found: found, terms: terms)
        case .records(let tagged): TaggedAnswerView(tagged: tagged)
        case .lastBought(let found, let terms): LastBoughtView(found: found, terms: terms)
        case .thing(let answer): ThingAnswerView(answer: answer)
        case .priceHistory(let history, let terms): PriceHistoryView(history: history, terms: terms)
        case .collection(let collection, let records): CollectionAnswerView(collection: collection, records: records)
        case .search(let hits, let text):
            if hits.isEmpty {
                NotFound(text: "Nothing in your archive mentions “\(text)”.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Records that mention it").font(Theme.display(.title3))
                    ForEach(hits) { hit in
                        NavigationLink(value: RecordListView.Destination(record: hit.record, pagePosition: hit.pagePosition)) {
                            SearchHitCard(hit: hit)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct SpendingAnswerView: View {
    @Environment(AppModel.self) private var model
    let answer: SpendingAnswer
    var reask: (SpendingQuery) -> Void
    var decided: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if answer.counted.isEmpty {
                NotFound(text: "I couldn't find any \(answer.scope) in your archive.")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(answer.scope.prefix(1).uppercased() + answer.scope.dropFirst())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(answer.totals, id: \.currency) { total in
                        Text(total.formatted)
                            .font(Theme.display(.largeTitle, weight: .bold))
                            .monospacedDigit()
                            .accessibilityIdentifier("answer-total")
                    }
                    Text(answer.counted.count == 1 ? "From 1 amount in your archive" : "From \(answer.counted.count) amounts in your archive")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if answer.counted.isEmpty, !answer.otherMonths.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your archive does have \(answer.subject) in")
                        .font(.subheadline.weight(.semibold))
                    ForEach(answer.otherMonths, id: \.label) { month in
                        Button {
                            var query = answer.query
                            query.range = month.range
                            query.rangeLabel = month.label
                            reask(query)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(month.label).font(.subheadline.weight(.medium))
                                    Text(month.count == 1 ? "1 amount" : "\(month.count) amounts")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(month.totals.map(\.formatted).joined(separator: " + "))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !answer.notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(answer.notes, id: \.self) { note in
                        Label(note, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !answer.counted.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What was counted").font(Theme.display(.title3))
                    VStack(spacing: 0) {
                        ForEach(Array(answer.counted.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider().padding(.leading) }
                            NavigationLink(value: RecordListView.Destination(record: item.record,
                                                                             pagePosition: item.transaction.pagePosition)) {
                                CountedRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                }
            }

            if !answer.duplicates.isEmpty {
                DisclosureGroup("Counted once (\(answer.duplicates.count))") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(answer.duplicates) { pair in
                            DuplicateCard(duplicate: pair) { isSame in
                                model.decide(pair, isSame: isSame)
                                decided()
                            }
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

}

struct CountedRow: View {
    let item: Counted

    var body: some View {
        HStack(spacing: 12) {
            RecordThumbnail(record: item.record, pagePosition: item.transaction.pagePosition, style: .square(40))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.transaction.merchant).font(.subheadline).lineLimit(1)
                Text("\(item.day.date().formatted(.dateTime.month(.abbreviated).day())) · \(item.record.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(item.transaction.kind == .refund ? "−\(item.transaction.money.formatted)" : item.transaction.money.formatted)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(item.transaction.kind == .refund ? Color.green : Color.primary)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private struct WhereAnswerView: View {
    let hits: [SearchHit]
    let terms: [String]

    var body: some View {
        if let best = hits.first {
            VStack(alignment: .leading, spacing: 14) {
                Text(best.record.kind == .item ? "From your note" : "The closest match")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("“\(best.snippet.text)”")
                    .font(Theme.display(.title2, weight: .semibold))
                NavigationLink(value: RecordListView.Destination(record: best.record, pagePosition: best.pagePosition)) {
                    SearchHitCard(hit: best)
                }
                .buttonStyle(.plain)
                if hits.count > 1 {
                    Text("Also mentioned in").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(hits.dropFirst()) { hit in
                        NavigationLink(value: RecordListView.Destination(record: hit.record, pagePosition: hit.pagePosition)) {
                            SearchHitCard(hit: hit)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            NotFound(text: "I couldn't find \(terms.isEmpty ? "that" : "“\(terms.joined(separator: " "))”") in your archive. Record a voice note next time you put it away.")
        }
    }
}

private struct ExpiryAnswerView: View {
    let found: [ExpiryFinding]
    let terms: [String]

    var body: some View {
        if found.isEmpty {
            NotFound(text: "I couldn't find an expiry date for \(terms.isEmpty ? "your warranties" : "“\(terms.joined(separator: " "))”") in your archive.")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(found, id: \.record.id) { finding in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(finding.record.title).font(.subheadline).foregroundStyle(.secondary)
                        Text(finding.day < Day(.now) ? "Expired \(formatted(finding.day))" : "Expires \(formatted(finding.day))")
                            .font(Theme.display(.title, weight: .bold))
                        Label(finding.isCalculated
                              ? "Worked out from the purchase date and “\(finding.evidence)”."
                              : "Printed as “\(finding.evidence)”.",
                              systemImage: "text.viewfinder")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        NavigationLink(value: RecordListView.Destination(record: finding.record)) {
                            Label("Open \(finding.record.title)", systemImage: "doc.text")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                }
            }
        }
    }

    private func formatted(_ day: Day) -> String {
        day.date().formatted(date: .long, time: .omitted)
    }
}

private struct NotFound: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "questionmark.folder")
        }
        .font(.headline)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

/// "Warranties for Mom": the records with those tags, as cards.
private struct TaggedAnswerView: View {
    let tagged: TaggedRecords

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tagged.headline).font(Theme.display(.title3))
            if tagged.records.isEmpty {
                NotFound(text: "Nothing saved is tagged with all of those.")
            } else {
                Text(tagged.records.count == 1 ? "1 record" : "\(tagged.records.count) records")
                    .font(.footnote).foregroundStyle(.secondary)
                ForEach(tagged.records) { record in
                    NavigationLink(value: RecordListView.Destination(record: record)) {
                        HStack(spacing: 12) {
                            RecordThumbnail(record: record, pagePosition: nil, style: .square(44))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                Text("\(record.kind.label) · \(record.effectiveDay.date().formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

extension TaggedRecords {
    /// "Warranties · Mom", "Everything · Boston".
    var headline: String {
        "\(kind?.pluralLabel ?? "Everything") · \(tags.map(\.name).joined(separator: " and "))"
    }
}

/// "When did I last buy eggs?": the latest receipt line, then earlier ones.
private struct LastBoughtView: View {
    let found: [Counted]
    let terms: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let latest = found.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last bought").font(.subheadline).foregroundStyle(.secondary)
                    Text(latest.day.date().formatted(date: .long, time: .omitted))
                        .font(Theme.display(.title, weight: .bold))
                    Text("\(latest.transaction.memo) at \(latest.transaction.merchant), \(latest.transaction.money.formatted)")
                        .font(.subheadline)
                }
                VStack(spacing: 0) {
                    ForEach(Array(found.prefix(10).enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading) }
                        NavigationLink(value: RecordListView.Destination(record: item.record, pagePosition: item.transaction.pagePosition)) {
                            CountedRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                Label("From the lines on your saved receipts.", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("No saved receipt lists “\(terms.joined(separator: " "))”. Only receipts that print each item can answer this.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A thing, with what the question was about first.
private struct ThingAnswerView: View {
    let answer: ThingAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if answer.isOutOfWarrantyList {
                Text(answer.profiles.isEmpty ? "Everything you've saved is still covered, or has no warranty date."
                                             : "\(answer.profiles.count) \(answer.profiles.count == 1 ? "thing is" : "things are") out of warranty")
                    .font(Theme.display(.title3))
                ForEach(answer.profiles) { profile in card(profile) }
            } else if let profile = answer.profiles.first {
                Text(headline(profile)).font(Theme.display(.title2, weight: .bold))
                if let detail = detail(profile) {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                card(profile)
                if answer.topic == .documents {
                    ForEach(profile.links) { link in
                        NavigationLink(value: RecordListView.Destination(record: link.record)) {
                            HStack(spacing: 12) {
                                RecordThumbnail(record: link.record, pagePosition: nil, style: .square(44))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(link.role.label).font(.caption.weight(.semibold)).foregroundStyle(link.record.kind.tint)
                                    Text(link.record.title).font(.subheadline).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func card(_ profile: ThingProfile) -> some View {
        NavigationLink { ThingProfileView(thingId: profile.id) } label: {
            HStack(spacing: 12) {
                ThingThumbnail(profile: profile)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.thing.name).font(.subheadline.weight(.semibold))
                    WarrantyLabel(profile: profile).font(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func headline(_ profile: ThingProfile) -> String {
        let thing = profile.thing
        switch answer.topic {
        case .bought:
            return thing.purchased.map { "Bought \($0.date().formatted(date: .long, time: .omitted))" } ?? "No purchase date saved"
        case .warranty:
            switch profile.warranty(on: Day(.now)) {
            case .covered(let until): return "Yes, covered until \(until.date().formatted(date: .long, time: .omitted))"
            case .ended(let on): return "No, the warranty ended \(on.date().formatted(date: .long, time: .omitted))"
            case .unknown: return "No warranty date saved"
            }
        case .value:
            return thing.value.map { "Paid \($0.formatted)" } ?? "No price saved"
        case .documents:
            return profile.links.isEmpty ? "No documents linked yet" : "\(profile.links.count) \(profile.links.count == 1 ? "document" : "documents")"
        case .overview:
            return thing.name
        }
    }

    private func detail(_ profile: ThingProfile) -> String? {
        let thing = profile.thing
        switch answer.topic {
        case .bought, .value:
            return [thing.store.isEmpty ? nil : "at \(thing.store)", thing.value?.formatted].compactMap { $0 }.joined(separator: ", ")
        case .warranty:
            return profile.warrantyEvidence.map { "From the warranty: “\($0)”" }
        default:
            return nil
        }
    }
}

/// "What did I pay for eggs last time?": latest, lowest, highest, average.
private struct PriceHistoryView: View {
    let history: PriceHistory?
    let terms: [String]

    var body: some View {
        if let history, let latest = history.latest {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last time").font(.subheadline).foregroundStyle(.secondary)
                    Text(latest.transaction.money.formatted).font(Theme.display(.largeTitle, weight: .bold)).monospacedDigit()
                    Text("\(latest.transaction.memo.isEmpty ? latest.transaction.merchant : latest.transaction.memo) at \(latest.transaction.merchant), \(latest.day.date().formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline)
                }
                if history.points.count > 1 {
                    HStack(spacing: 10) {
                        stat("Lowest", history.lowest, history.currency)
                        stat("Highest", history.highest, history.currency)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Average").font(.caption).foregroundStyle(.secondary)
                            Text(Money(cents: history.averageCents, currency: history.currency).formatted).font(.headline).monospacedDigit()
                            Text("\(history.points.count) times").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if history.changeCents != 0, let first = history.first {
                        Label("\(history.changeCents > 0 ? "Up" : "Down") \(Money(cents: abs(history.changeCents), currency: history.currency).formatted) since \(first.day.date().formatted(.dateTime.month(.abbreviated).year()))",
                              systemImage: history.changeCents > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(history.changeCents > 0 ? Color.orange : Color.green)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(history.points.reversed().prefix(12).enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading) }
                        NavigationLink(value: RecordListView.Destination(record: item.record, pagePosition: item.transaction.pagePosition)) {
                            CountedRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                Label(history.isPurchases ? "From whole purchases, since receipts don't list it as a line."
                                          : "From the lines on your saved receipts.", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            Text("No saved receipt lists “\(terms.joined(separator: " "))”. Only receipts that print each item can answer this.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func stat(_ title: String, _ item: Counted?, _ currency: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(item?.transaction.money.formatted ?? "—").font(.headline).monospacedDigit()
            Text(item?.transaction.merchant ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// "Show everything for the house": the collection's records.
private struct CollectionAnswerView: View {
    let collection: Collection
    let records: [Record]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink { CollectionView(collectionId: collection.id) } label: {
                Label("\(collection.name) · \(records.count) \(records.count == 1 ? "record" : "records")", systemImage: collection.symbol)
                    .font(Theme.display(.title3))
            }
            .buttonStyle(.plain)
            ForEach(records.prefix(15)) { record in
                NavigationLink(value: RecordListView.Destination(record: record)) {
                    HStack(spacing: 12) {
                        RecordThumbnail(record: record, pagePosition: nil, style: .square(44))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.title).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text("\(record.kind.label) · \(record.effectiveDay.date().formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
