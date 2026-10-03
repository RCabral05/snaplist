import ArchiveCore
import SwiftUI

/// Search and the filter on one line, at the top of the Library.
struct LibrarySearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Stores, amounts, any word", text: $text)
                    .focused($isFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("library-search")
                if !text.isEmpty {
                    Button {
                        text = ""
                        isFocused = false
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Theme.surface, in: .capsule)
            .overlay(Capsule().strokeBorder(Theme.border))
            .contentShape(.capsule)
            .onTapGesture { isFocused = true }

            LibraryFilterMenu()
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(Theme.surface, in: .circle)
                .overlay(Circle().strokeBorder(Theme.border))
        }
        .padding(.horizontal)
    }
}

/// The Library's filter: a button that opens a menu of record types, then
/// people and places. Filled in while a filter is on.
struct LibraryFilterMenu: View {
    @Environment(AppModel.self) private var model

    private var isFiltering: Bool { model.kindFilter != nil || model.tagFilter != nil }

    var body: some View {
        Menu {
            Button {
                model.kindFilter = nil
                model.tagFilter = nil
            } label: {
                checked("Show All", "square.grid.2x2", !isFiltering)
            }
            Section("Type") {
                ForEach(model.kindCounts, id: \.kind) { entry in
                    Button {
                        model.kindFilter = model.kindFilter == entry.kind ? nil : entry.kind
                    } label: {
                        checked("\(entry.kind.pluralLabel) (\(entry.count))", entry.kind.symbol, model.kindFilter == entry.kind)
                    }
                }
            }
            if !model.tags.isEmpty {
                Section("People and places") {
                    ForEach(model.tags) { tag in
                        Button {
                            model.tagFilter = model.tagFilter?.id == tag.id ? nil : tag
                        } label: {
                            checked("\(tag.name) (\(model.recordCount(of: tag)))", tag.kind.symbol, model.tagFilter?.id == tag.id)
                        }
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("library-filter")
        .sensoryFeedback(.selection, trigger: model.kindFilter)
        .sensoryFeedback(.selection, trigger: model.tagFilter)
    }

    /// A menu row with a checkmark when it's the one showing.
    private func checked(_ title: String, _ symbol: String, _ on: Bool) -> some View {
        Label(title, systemImage: on ? "checkmark" : symbol)
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
