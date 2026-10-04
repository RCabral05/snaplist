import ArchiveCore
import SwiftUI

/// Pick records from the library: to put in a collection, the car's history
/// or the tax report.
struct RecordPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let title: String
    /// Already in, so not offered.
    var excluding: Set<UUID> = []
    var action = "Add"
    var done: ([UUID]) -> Void

    @State private var query = ""
    @State private var picked: Set<UUID> = []

    private var records: [Record] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        return model.records.filter { record in
            !excluding.contains(record.id)
                && (words.isEmpty || words.allSatisfy { word in
                    record.title.lowercased().contains(word) || record.kind.label.lowercased().contains(word)
                })
        }
    }

    var body: some View {
        NavigationStack {
            List(records) { record in
                Button {
                    if picked.contains(record.id) { picked.remove(record.id) } else { picked.insert(record.id) }
                } label: {
                    HStack(spacing: 12) {
                        RecordThumbnail(record: record, pagePosition: nil, style: .square(40))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.title).font(.subheadline).lineLimit(1)
                            Text("\(record.kind.label) · \(record.effectiveDay.date().formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: picked.contains(record.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(picked.contains(record.id) ? Theme.accent : Color.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .overlay {
                if records.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "Nothing else to add" : "No matches", systemImage: "tray")
                }
            }
            .searchable(text: $query, prompt: "Search your library")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(picked.isEmpty ? action : "\(action) \(picked.count)") {
                        // In the library's order, newest first.
                        done(model.records.map(\.id).filter(picked.contains))
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                }
            }
        }
    }
}
