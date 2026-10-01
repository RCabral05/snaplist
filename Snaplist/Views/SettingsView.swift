import SwiftUI

struct SettingsView: View {
    @Environment(AppLock.self) private var lock
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
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

                Section("Where your data is") {
                    Label("Only on this iPhone. There is no account, and nothing is uploaded.", systemImage: "iphone")
                    Label("Encrypted by iOS while your iPhone is locked.", systemImage: "lock.shield")
                    Label("Text is read on the iPhone itself, never by a server.", systemImage: "text.viewfinder")
                    Label("Included in your iPhone's own backups (iCloud or computer), which belong to your Apple ID.", systemImage: "externaldrive")
                }
                .font(.subheadline)

                Section {
                    LabeledContent("Version", value: version)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
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
