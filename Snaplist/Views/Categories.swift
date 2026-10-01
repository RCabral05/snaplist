import ArchiveCore
import SwiftUI

/// "All · Receipts 4 · Warranties 1": one chip per category in use. Narrows
/// both the list and search.
struct KindFilterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", count: nil, isSelected: model.kindFilter == nil) {
                    model.kindFilter = nil
                }
                ForEach(model.kindCounts, id: \.kind) { entry in
                    chip(entry.kind.pluralLabel, count: entry.count, isSelected: model.kindFilter == entry.kind) {
                        model.kindFilter = model.kindFilter == entry.kind ? nil : entry.kind
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

    @ViewBuilder
    private func chip(_ title: String, count: Int?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let label = Text(count.map { "\(title) \($0)" } ?? title)
        if isSelected {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .accessibilityAddTraits(.isSelected)
        } else {
            Button(action: action) { label }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
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
                Section("Category") {
                    Picker("Category", selection: $kind) {
                        ForEach(RecordKind.allCases, id: \.self) { kind in
                            Label(kind.label, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
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
