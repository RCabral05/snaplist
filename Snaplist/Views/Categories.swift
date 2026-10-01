import ArchiveCore
import SwiftUI

/// "All · Receipts 4 · Warranties 1": one chip per category in use, each in
/// its colour. Narrows both the grid and search.
struct KindFilterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: "All", symbol: "square.grid.2x2", count: nil, tint: .accentColor,
                     isSelected: model.kindFilter == nil) {
                    model.kindFilter = nil
                }
                ForEach(model.kindCounts, id: \.kind) { entry in
                    Chip(title: entry.kind.pluralLabel, symbol: entry.kind.symbol, count: entry.count,
                         tint: entry.kind.tint, isSelected: model.kindFilter == entry.kind) {
                        model.kindFilter = model.kindFilter == entry.kind ? nil : entry.kind
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: model.kindFilter)
    }

    private struct Chip: View {
        let title: String
        let symbol: String
        let count: Int?
        let tint: Color
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: symbol).font(.caption.weight(.semibold))
                    Text(title)
                    if let count {
                        Text("\(count)")
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.12)), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .animation(.snappy(duration: 0.2), value: isSelected)
        }
    }
}

/// A "Category" submenu with a checkmark on the current one.
struct CategoryMenu: View {
    @Environment(AppModel.self) private var model
    let record: Record

    var body: some View {
        Menu("Category", systemImage: "tag") {
            ForEach(RecordKind.allCases, id: \.self) { kind in
                Button {
                    model.setKind(kind, for: record)
                } label: {
                    if kind == record.kind {
                        Label(kind.label, systemImage: "checkmark")
                    } else {
                        Label(kind.label, systemImage: kind.symbol)
                    }
                }
            }
        }
    }
}

/// Name and category. More fields (date, merchant, place) arrive with
/// extraction; this is the screen they will join.
struct EditRecordView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let record: Record
    @State private var title: String
    @State private var kind: RecordKind

    init(record: Record) {
        self.record = record
        _title = State(initialValue: record.title)
        _kind = State(initialValue: record.kind)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $title)
                        .submitLabel(.done)
                }
                .listRowBackground(Theme.surface)
                Section("Category") {
                    Picker("Category", selection: $kind) {
                        ForEach(RecordKind.allCases, id: \.self) { kind in
                            Label(kind.label, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                .listRowBackground(Theme.surface)
            }
            .warmForm()
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = record
                        updated.title = trimmedTitle
                        updated.kind = kind
                        model.update(updated)
                        dismiss()
                    }
                    .disabled(trimmedTitle.isEmpty)
                }
            }
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
