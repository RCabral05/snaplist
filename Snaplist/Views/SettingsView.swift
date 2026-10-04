import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppLock.self) private var lock
    @Environment(\.dismiss) private var dismiss

    @AppStorage(QuestionInterpreter.settingKey) private var useAppleIntelligence = true
    @AppStorage(Spotlight.settingKey) private var showInSpotlight = false
    @AppStorage(Reminders.settingKey) private var remindersEnabled = false
    @AppStorage(PhotoPlaces.settingKey) private var namePlaces = false
    @State private var remindersDenied = false

    @State private var export: ExportState = .idle
    @State private var isConfirmingDelete = false
    @State private var deleted = false

    enum ExportState {
        case idle, working
        case ready(URL, String)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ThemePicker()
                    } label: {
                        LabeledContent("Theme", value: Theme.current.name)
                    }
                } header: {
                    Text("Appearance")
                }
                .listRowBackground(Theme.surface)

                Section {
                    Toggle("Require \(AppLock.methodName)", isOn: lockBinding)
                        .disabled(!AppLock.isAvailable)
                } header: {
                    Text("Lock")
                } footer: {
                    if AppLock.isAvailable {
                        Text("Asked when Snaplist opens, and when you come back after more than \(Int(AppLock.gracePeriod)) seconds away. Your iPhone passcode works if \(AppLock.methodName) doesn't.")
                    } else {
                        Text("Set a passcode in the Settings app to lock Snaplist.")
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    Toggle("Use Apple Intelligence", isOn: $useAppleIntelligence)
                        .disabled(!QuestionInterpreter.isAvailable)
                } header: {
                    Text("Questions")
                } footer: {
                    Text(QuestionInterpreter.status)
                }
                .listRowBackground(Theme.surface)

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("“Hey Siri, ask Snaplist”")
                            Text("or “How much did I spend on gas in Snaplist?”")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "waveform")
                    }
                    Toggle("Show in Spotlight", isOn: $showInSpotlight)
                        .onChange(of: showInSpotlight) { model.updateSpotlight() }
                } header: {
                    Text("Siri and Search")
                } footer: {
                    Text(lock.isEnabled
                         ? "With the lock on, Siri opens Snaplist to show answers after you unlock it. Spotlight shows record names, dates and totals, but never what's written on a page, and doesn't ask for \(AppLock.methodName)."
                         : "Siri answers out loud while your iPhone is unlocked. Spotlight shows record names, dates and totals, but never what's written on a page.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    NavigationLink {
                        ConnectionsView()
                    } label: {
                        Label("Apple Pay, Banks and Cards", systemImage: "creditcard")
                    }
                } header: {
                    Text("Live charges")
                } footer: {
                    Text("Log Apple Pay taps as you pay, or connect banks and cards through SimpleFIN.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    Toggle("Bills, Renewals and Budgets", isOn: $remindersEnabled)
                        .onChange(of: remindersEnabled) { _, enabled in
                            Task {
                                if enabled, !(await Reminders.requestPermission()) {
                                    remindersEnabled = false
                                    remindersDenied = true
                                }
                                model.updateReminders()
                            }
                        }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text(remindersDenied
                         ? "Notifications are off for Snaplist. Turn them on in the Settings app under Notifications, then try again."
                         : "Notifications before a bill is due or a return window closes (3 days), a warranty ends (30 days) or an ID or policy needs renewing (60 days), when a budget passes 80% or 100%, and a recap of last month on the 1st. Names and amounts can show on the Lock Screen; with the lock on, budget amounts don't.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    Toggle("Name Places from Photos", isOn: $namePlaces)
                } header: {
                    Text("People and places")
                } footer: {
                    Text("When a photo you add has a location saved in it, tag it with the town, like Boston. Finding the town's name sends that location (never the photo) to Apple's map service; nothing else leaves your iPhone.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    NavigationLink {
                        AlwaysHideView()
                    } label: {
                        LabeledContent("Always Hide", value: RedactedCopy.words.isEmpty ? "Not set" : "\(RedactedCopy.words.count)")
                    }
                } header: {
                    Text("Sharing")
                } footer: {
                    Text("Your name, street or phone, covered whenever you share with private details hidden.")
                }
                .listRowBackground(Theme.surface)

                Section("Where your data is") {
                    Label(SimpleFIN.isConnected
                          ? "Only on this iPhone. There is no account, and nothing is uploaded; bank charges are downloaded from SimpleFIN."
                          : "Only on this iPhone. There is no account, and nothing is uploaded.", systemImage: "iphone")
                    Label("Encrypted by iOS while your iPhone is locked.", systemImage: "lock.shield")
                    Label("Text is read, and questions understood, on the iPhone itself, never by a server.", systemImage: "text.viewfinder")
                    Label("Included in your iPhone's own backups (iCloud or computer), which belong to your Apple ID.", systemImage: "externaldrive")
                }
                .font(.subheadline)
                .listRowBackground(Theme.surface)

                Section {
                    exportRow
                    Button("Delete Everything", role: .destructive) { isConfirmingDelete = true }
                        .disabled(model.records.isEmpty)
                        // On the button, so iOS points the confirmation at it.
                        .confirmationDialog("Delete everything in Snaplist?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                            Button("Delete \(model.records.count) Records", role: .destructive) {
                                Task {
                                    guard await AppLock.confirmOwner("Delete everything in Snaplist") else { return }
                                    await model.deleteEverything()
                                    export = .idle
                                    deleted = true
                                }
                            }
                        } message: {
                            Text("Every original, its text and amounts, and your corrections are removed from this iPhone. This can't be undone. Export first if you want a copy.")
                        }
                } header: {
                    Text("Your data")
                } footer: {
                    Text(deleted
                         ? "Everything was deleted from this iPhone."
                         : "Export makes a zip of every original as you saved it, the text read from each, and spreadsheets (CSV) of your records and amounts. Delete Everything removes all of it from this iPhone; copies already in a backup or an export aren't affected.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    LabeledContent("Version", value: version)
                }
                .listRowBackground(Theme.surface)
            }
            .warmForm()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder private var exportRow: some View {
        switch export {
        case .idle:
            Button("Export Everything", systemImage: "square.and.arrow.up.on.square") { startExport() }
                .disabled(model.records.isEmpty)
        case .working:
            HStack {
                Text("Preparing export…")
                Spacer()
                ProgressView()
            }
        case .ready(let url, let summary):
            ShareLink(item: url) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save or Share \(url.lastPathComponent)")
                        Text(summary).font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "doc.zipper")
                }
            }
        case .failed(let message):
            Button("Export Everything", systemImage: "square.and.arrow.up.on.square") { startExport() }
            Text(message).font(.footnote).foregroundStyle(.red)
        }
    }

    private func startExport() {
        export = .working
        Task {
            do {
                let (url, summary) = try await model.exportArchive()
                let records = summary.records == 1 ? "1 record" : "\(summary.records) records"
                let files = summary.files == 1 ? "1 original" : "\(summary.files) originals"
                let amounts = summary.amounts == 1 ? "1 amount" : "\(summary.amounts) amounts"
                export = .ready(url, "\(records), \(files), \(amounts)")
            } catch {
                export = .failed("Couldn't export: \(error.localizedDescription)")
            }
        }
    }

    private var lockBinding: Binding<Bool> {
        Binding(get: { lock.isEnabled }, set: { enabled in Task { await lock.setEnabled(enabled) } })
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

/// The person's own words to hide when sharing, one per row.
private struct AlwaysHideView: View {
    @AppStorage(RedactedCopy.wordsKey) private var stored = ""
    @State private var words: [String] = []
    @State private var newWord = ""
    @FocusState private var isAdding: Bool

    var body: some View {
        Form {
            Section {
                ForEach(words, id: \.self) { word in
                    Text(word)
                }
                .onDelete { offsets in
                    words.remove(atOffsets: offsets)
                    save()
                }
                HStack {
                    TextField("Add your name, street or phone", text: $newWord)
                        .focused($isAdding)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).count < 3)
                }
            } footer: {
                Text("Any line that has one of these is covered when you share with private details hidden. Add your first and last name separately to catch either on its own. A phone number is found however it's printed. Swipe left to remove one.")
            }
            .listRowBackground(Theme.surface)
        }
        .warmForm()
        .navigationTitle("Always Hide")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { words = RedactedCopy.words }
    }

    private func add() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard word.count >= 3, !words.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else { return }
        words.append(word)
        newWord = ""
        isAdding = true
        save()
    }

    private func save() {
        stored = words.joined(separator: "\n")
    }
}
