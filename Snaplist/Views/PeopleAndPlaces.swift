import ArchiveCore
import SwiftUI

/// Who a record is for and where it's from, as removable chips, with a way
/// to add more. Shown on every record.
struct TagsSection: View {
    @Environment(AppModel.self) private var model
    let record: Record

    @State private var adding: TagKind?

    private var tags: [Tag] { model.tagsByRecord[record.id] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("People, places and taxes")
                .font(Theme.display(.title3))
                .padding(.horizontal, 4)
            FlowLayout(spacing: 8) {
                ForEach(tags) { tag in
                    Menu {
                        Button("Show All Tagged \(tag.name)", systemImage: "line.3.horizontal.decrease") {
                            model.kindFilter = nil
                            model.tagFilter = tag
                            model.pendingLink = .library
                        }
                        Button("Remove", systemImage: "xmark", role: .destructive) {
                            model.removeTag(tag, from: record.id)
                        }
                    } label: {
                        Label(tag.name, systemImage: tag.kind.symbol)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(tag.kind.tint)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(tag.kind.tint.opacity(0.13), in: .capsule)
                    }
                }
                ForEach(TagKind.allCases, id: \.self) { kind in
                    Button {
                        adding = kind
                    } label: {
                        Label(kind.label, systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .overlay(Capsule().strokeBorder(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(kind == .tax ? "Mark for taxes" : "Add a \(kind.label.lowercased())")
                }
            }
            if tags.isEmpty {
                Text("Tag who it's for, where it's from, or what it is at tax time, then ask “Mom's warranties” or “receipts from Boston”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal)
        .sheet(item: $adding) { kind in
            TagPicker(kind: kind, record: record)
                .presentationDetents([.medium, .large])
        }
    }
}

extension TagKind: @retroactive Identifiable {
    public var id: String { rawValue }
}

/// Pick an existing person or place, or type a new one.
private struct TagPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let kind: TagKind
    let record: Record

    @State private var name = ""
    @FocusState private var isFocused: Bool

    private var existing: [Tag] {
        let mine = Set((model.tagsByRecord[record.id] ?? []).compactMap(\.id))
        let mineNames = Set((model.tagsByRecord[record.id] ?? []).filter { $0.kind == kind }.map { $0.name.lowercased() })
        let typed = name.trimmingCharacters(in: .whitespaces).lowercased()
        var tags = model.tags.filter { tag in
            tag.kind == kind && !mine.contains(tag.id ?? -1) && (typed.isEmpty || tag.name.lowercased().contains(typed))
        }
        // Tax purposes start with the usual ones, used or not.
        if kind == .tax {
            for suggestion in TagKind.taxSuggestions where !tags.contains(where: { $0.name.lowercased() == suggestion.lowercased() })
                && !mineNames.contains(suggestion.lowercased())
                && (typed.isEmpty || suggestion.lowercased().contains(typed)) {
                tags.append(Tag(kind: .tax, name: suggestion))
            }
        }
        return tags
    }

    private var canCreate: Bool {
        let typed = name.trimmingCharacters(in: .whitespaces)
        return !typed.isEmpty && !model.tags.contains { $0.kind == kind && $0.name.caseInsensitiveCompare(typed) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(placeholder, text: $name)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit(addTyped)
                    if canCreate {
                        Button("Add “\(name.trimmingCharacters(in: .whitespaces))”", systemImage: "plus.circle.fill", action: addTyped)
                    }
                }
                .listRowBackground(Theme.surface)

                if !existing.isEmpty {
                    Section(kind == .person ? "People" : kind == .place ? "Places" : "Purposes") {
                        ForEach(existing, id: \.name) { tag in
                            Button {
                                model.addTag(tag.name, kind: kind, to: record.id)
                                dismiss()
                            } label: {
                                Label(tag.name, systemImage: kind.symbol)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .warmForm()
            .navigationTitle(kind == .tax ? "Mark for Taxes" : "Add \(kind.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { isFocused = existing.isEmpty }
        }
    }

    private var placeholder: String {
        switch kind {
        case .person: "Name, like Mom or Work"
        case .place: "Place, like Boston or Lake House"
        case .tax: "Purpose, like Business or Medical"
        }
    }

    private func addTyped() {
        let typed = name.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return }
        model.addTag(typed, kind: kind, to: record.id)
        dismiss()
    }
}

/// Lays chips out in rows, wrapping like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
