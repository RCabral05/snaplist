import StoreKit
import SwiftUI

/// The paywall: what Pro adds, the two plans with their App Store prices,
/// and restoring a purchase made on another iPhone.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let reason: ProFeature
    private var pro: Pro { Pro.shared }

    @State private var selected: String = Pro.yearlyID
    @State private var working = false
    @State private var message: String?

    private let highlights: [ProFeature] = [.records, .spending, .liveCharges, .subscriptions, .statementCheck, .car, .things,
                                            .taxReport, .privateShare, .collections, .themes]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Snaplist Pro").font(Theme.display(.largeTitle, weight: .bold))
                        Text(reason.summary).font(.subheadline).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(highlights) { feature in
                            Label {
                                Text(feature.title).font(.subheadline.weight(feature == reason ? .semibold : .regular))
                            } icon: {
                                Image(systemName: feature.symbol).foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    plans
                    Button {
                        Task { await subscribe() }
                    } label: {
                        Group {
                            if working { ProgressView() } else { Text(buttonTitle).font(.headline) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(working || pro.products.isEmpty)
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Your records stay yours either way: everything you've saved can always be opened, searched, exported and deleted. Payment is charged to your Apple Account. A subscription renews automatically unless it's cancelled at least 24 hours before the end of the period; manage or cancel it in Settings → Apple Account → Subscriptions.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 18) {
                        Button("Restore Purchases") { Task { await restore() } }
                        Link("Terms of Use", destination: Pro.termsURL)
                        if let privacy = Pro.privacyURL { Link("Privacy Policy", destination: privacy) }
                    }
                    .font(.footnote)
                }
                .padding()
            }
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not Now") { dismiss() } }
            }
            .onChange(of: pro.isUnlocked) { if pro.isUnlocked { dismiss() } }
        }
    }

    @ViewBuilder private var plans: some View {
        if pro.products.isEmpty {
            Text("Plans aren't available right now. Check your connection and try again.")
                .font(.footnote).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 10) {
                ForEach(pro.products, id: \.id) { product in
                    Button { selected = product.id } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.id == Pro.yearlyID ? "Yearly" : "Monthly").font(.headline)
                                Text(detail(product)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(product.displayPrice).font(.headline).monospacedDigit()
                            Image(systemName: selected == product.id ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selected == product.id ? Theme.accent : Color.secondary)
                        }
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
                            .strokeBorder(selected == product.id ? Theme.accent : Theme.border, lineWidth: selected == product.id ? 2 : 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var selectedProduct: Product? { pro.products.first { $0.id == selected } ?? pro.products.first }

    private var buttonTitle: String {
        guard let product = selectedProduct else { return "Subscribe" }
        if let trial = trialText(product) { return "Start \(trial)" }
        return "Subscribe for \(product.displayPrice)"
    }

    private func detail(_ product: Product) -> String {
        let period = product.id == Pro.yearlyID ? "a year" : "a month"
        if let trial = trialText(product) { return "\(trial), then \(product.displayPrice) \(period)" }
        return "\(product.displayPrice) \(period)"
    }

    /// "7-day free trial", when the plan has one.
    private func trialText(_ product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let count = offer.period.value
        let unit = switch offer.period.unit {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        @unknown default: "day"
        }
        return "\(count)-\(unit) free trial"
    }

    private func subscribe() async {
        guard let product = selectedProduct else { return }
        working = true
        defer { working = false }
        do {
            if try await pro.purchase(product) { dismiss() }
        } catch {
            message = "The App Store couldn't complete that: \(error.localizedDescription)"
        }
    }

    private func restore() async {
        working = true
        defer { working = false }
        await pro.restore()
        message = pro.isUnlocked ? nil : "No Snaplist Pro subscription was found for this Apple Account."
    }
}

/// Shows `content` with Pro, or what it would show and a way to get it.
struct ProLocked<Content: View>: View {
    let feature: ProFeature
    @ViewBuilder var content: () -> Content

    var body: some View {
        if Pro.shared.isUnlocked {
            content()
        } else {
            ScrollView {
                ProTeaser(feature: feature).padding()
            }
            .background(Theme.background)
            .navigationTitle(feature.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// A card that says what Pro would show here.
struct ProTeaser: View {
    let feature: ProFeature

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: feature.symbol)
                .font(.system(size: 36))
                .foregroundStyle(Theme.accent)
            Text(feature.title).font(Theme.display(.title3, weight: .bold)).multilineTextAlignment(.center)
            Text(feature.summary).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button {
                Pro.shared.paywall = feature
            } label: {
                Label("Unlock with Pro", systemImage: "lock.open").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
    }
}

/// Settings: the subscription, restoring it, and in TestFlight a switch to
/// try the app with and without Pro.
struct ProSettingsSection: View {
    @State private var isManaging = false
    private var pro: Pro { Pro.shared }

    var body: some View {
        Section {
            if pro.hasSubscription {
                Label("Snaplist Pro is on", systemImage: "checkmark.seal.fill")
                Button("Manage Subscription") { isManaging = true }
            } else {
                Button {
                    pro.paywall = .records
                } label: {
                    Label("Get Snaplist Pro", systemImage: "sparkles")
                }
                Button("Restore Purchases") { Task { await pro.restore() } }
            }
            if pro.isTestBuild {
                Toggle("Pro for Testing", isOn: Binding(
                    get: { pro.isUnlocked },
                    set: { pro.testOverride = $0 }))
                SampleDataToggle()
            }
        } header: {
            Text("Snaplist Pro")
        } footer: {
            Text(pro.isTestBuild
"                 ? "Pro for Testing and Sample Data only appear in TestFlight builds. Sample Data swaps in made-up records, for trying everything and taking screenshots; your own records are kept aside and come back when it's off."
                 : "Free keeps up to \(Pro.freeRecordLimit) records and \(Pro.freeCollectionLimit) collections. Everything you've saved can always be opened, exported and deleted.")
        }
        .listRowBackground(Theme.surface)
        .manageSubscriptionsSheet(isPresented: $isManaging)
    }
}

/// TestFlight only: switches between your archive and the sample one.
/// The archive is opened at launch, so Snaplist closes to switch.
struct SampleDataToggle: View {
    @State private var isOn = UserDefaults.standard.bool(forKey: "sampleDataOn")
    @State private var isConfirming = false

    var body: some View {
        Toggle("Sample Data", isOn: Binding(get: { isOn }, set: { _ in isConfirming = true }))
            .confirmationDialog(isOn ? "Back to your records?" : "Show sample data?", isPresented: $isConfirming,
                                titleVisibility: .visible) {
                Button("Switch and Close Snaplist") {
                    UserDefaults.standard.set(!isOn, forKey: "sampleDataOn")
                    UserDefaults.standard.synchronize()
                    exit(0)
                }
            } message: {
                Text(isOn
                     ? "Snaplist closes. Open it again to see your own records; the samples are kept for next time."
                     : "Snaplist closes. Open it again to find it full of made-up receipts, bills and statements. Your own records are kept aside, untouched.")
            }
    }
}

extension View {
    /// Shows the paywall when Pro is asked for. On the app's root, and again
    /// on screens that are themselves sheets (Settings), since iOS shows a
    /// sheet only from the screen on top.
    func paywallSheet() -> some View {
        sheet(item: Binding(get: { Pro.shared.paywall }, set: { Pro.shared.paywall = $0 })) { reason in
            PaywallView(reason: reason)
        }
    }
}
