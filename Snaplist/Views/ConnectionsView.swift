import ArchiveCore
import SwiftUI

/// Charges that come in on their own: Apple Pay taps through a Shortcuts
/// automation, and banks and cards through SimpleFIN.
struct ConnectionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    @State private var isConnected = SimpleFIN.isConnected
    @State private var token = ""
    @State private var working = false
    @State private var message: String?
    @State private var failed = false
    @State private var isConfirmingDisconnect = false
    @State private var appleCardOn = AppleCard.isEnabled
    @State private var appleCardWorking = false
    @State private var appleCardMessage: String?

    var body: some View {
        Form {
            if AppleCard.isAvailable {
            Section {
                if appleCardOn {
                    if let last = AppleCard.lastSync {
                        LabeledContent("Last checked", value: last.formatted(.relative(presentation: .named)))
                    }
                    Button {
                        Task { await syncAppleCard() }
                    } label: {
                        if appleCardWorking { ProgressView() } else { Label("Check Now", systemImage: "arrow.clockwise") }
                    }
                    .disabled(appleCardWorking)
                    Button("Turn Off", role: .destructive) {
                        AppleCard.disconnect()
                        appleCardOn = false
                        appleCardMessage = nil
                    }
                } else {
                    Button {
                        Task {
                            appleCardWorking = true
                            defer { appleCardWorking = false }
                            do {
                                try await AppleCard.connect()
                                appleCardOn = true
                                await syncAppleCard()
                            } catch {
                                appleCardMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        if appleCardWorking { ProgressView() } else { Label("Connect Apple Card", systemImage: "creditcard.fill") }
                    }
                    .disabled(appleCardWorking)
                }
                if let appleCardMessage {
                    Text(appleCardMessage).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Apple Card")
            } footer: {
                Text("Every Apple Card, Apple Cash and Savings transaction, in stores, in apps and online, read from Wallet on this iPhone. Nothing goes through a server. Checked when Snaplist opens.")
            }
            .listRowBackground(Theme.surface)
            }

            Section {
                step(1, "In the Shortcuts app, open the Automation tab at the bottom and tap +.")
                step(2, "Scroll the list of triggers to Wallet (called Transaction on some iOS versions), pick your cards, and choose Run Immediately.")
                step(3, "Tap New Blank Automation, then Add Action, and search for Log a Charge.")
                step(4, "Tap each blue field and choose from Shortcut Input: Merchant, Amount, and the card's name for Card.")
                Button("Open Shortcuts", systemImage: "arrow.up.forward.app") {
                    openURL(URL(string: "shortcuts://")!)
                }
            } header: {
                Text("Apple Pay taps")
            } footer: {
                Text("Each tap is logged the moment you pay, on that card's statement for the month in Snaplist. A receipt you scan for it, or the card's statement when you import it, is counted once with it. Online purchases and swiped cards come in with the statement.")
            }
            .listRowBackground(Theme.surface)

            Section {
                if isConnected {
                    let accounts = UserDefaults.standard.stringArray(forKey: SimpleFIN.accountsKey) ?? []
                    ForEach(accounts, id: \.self) { account in
                        Label(account, systemImage: "creditcard")
                    }
                    if let last = SimpleFIN.lastSync {
                        LabeledContent("Last checked", value: last.formatted(.relative(presentation: .named)))
                    }
                    Button {
                        Task { await sync() }
                    } label: {
                        if working { ProgressView() } else { Label("Check Now", systemImage: "arrow.clockwise") }
                    }
                    .disabled(working)
                    Button("Disconnect", role: .destructive) { isConfirmingDisconnect = true }
                        .confirmationDialog("Disconnect SimpleFIN?", isPresented: $isConfirmingDisconnect, titleVisibility: .visible) {
                            Button("Disconnect", role: .destructive) {
                                SimpleFIN.disconnect()
                                isConnected = false
                                message = nil
                            }
                        } message: {
                            Text("Charges already in Snaplist stay. To stop SimpleFIN reading your bank too, remove the connection on SimpleFIN's site.")
                        }
                } else {
                    Link(destination: SimpleFIN.siteURL) {
                        Label("Get a Setup Token from SimpleFIN", systemImage: "arrow.up.forward.square")
                    }
                    TextField("Paste the setup token", text: $token, axis: .vertical)
                        .lineLimit(1...3)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                    Button {
                        Task { await connect() }
                    } label: {
                        if working { ProgressView() } else { Text("Connect") }
                    }
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || working)
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(failed ? Color.red : Color.secondary)
                }
            } header: {
                Text("Banks and cards")
            } footer: {
                Text("SimpleFIN Bridge is a paid service, separate from Snaplist, that reads transactions from many US banks and card companies. You link your banks on its site; Snaplist then downloads posted charges, checking at most every few hours. Your transactions pass through SimpleFIN and the company it uses to reach your bank. Snaplist sends nothing back, can't move money, and keeps the connection in the Keychain on this iPhone only.")
            }
            .listRowBackground(Theme.surface)
        }
        .warmForm()
        .navigationTitle("Live Charges")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func syncAppleCard() async {
        appleCardWorking = true
        defer { appleCardWorking = false }
        do {
            let added = try await model.syncAppleCard()
            appleCardMessage = added == 0 ? "Up to date." : added == 1 ? "1 new charge." : "\(added) new charges."
        } catch {
            appleCardMessage = error.localizedDescription
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Text("\(number)").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
        }
    }

    private func connect() async {
        working = true
        defer { working = false }
        do {
            try await SimpleFIN.connect(setupToken: token)
            token = ""
            isConnected = true
            await sync()
        } catch {
            failed = true
            message = error.localizedDescription
        }
    }

    private func sync() async {
        working = true
        defer { working = false }
        do {
            let added = try await model.syncBanks()
            failed = false
            message = added == 0 ? "Up to date." : added == 1 ? "1 new charge." : "\(added) new charges."
        } catch {
            failed = true
            message = error.localizedDescription
        }
    }
}
