import Observation
import SwiftUI
import UIKit

/// One look for the whole app: colours, typeface and shape. Picked from the
/// theme library in Settings.
struct AppTheme: Identifiable, Equatable, Sendable {
    enum ID: String, CaseIterable, Sendable {
        case ledger, vault, clarity
    }

    let id: ID
    let name: String
    let summary: String
    let accent: Color
    let onAccent: Color
    let background: Color
    let surface: Color
    let border: Color
    /// Headings and numbers: serif, default or rounded.
    let design: Font.Design
    /// Heavier headings for themes that want them.
    let boldness: Int
    let cardRadius: CGFloat
    /// Nil follows the iPhone's light or dark setting.
    let colorScheme: ColorScheme?

    func weight(_ weight: Font.Weight) -> Font.Weight {
        guard boldness > 0 else { return weight }
        switch weight {
        case .regular, .medium: return .semibold
        case .semibold: return .bold
        case .bold: return .heavy
        default: return weight
        }
    }

    static func == (a: AppTheme, b: AppTheme) -> Bool { a.id == b.id }

    /// Refined paper: cream and ink, serif numbers, a rust accent. Always
    /// light, as drawn.
    static let ledger = AppTheme(
        id: .ledger, name: "Ledger", summary: "Warm paper, serif numbers",
        accent: Color(light: 0x9A3412, dark: 0xF5B942),
        onAccent: Color(light: 0xFFFCF6, dark: 0x1C1A17),
        background: Color(light: 0xF4EFE6, dark: 0x1C1A17),
        surface: Color(light: 0xFFFCF6, dark: 0x2A2723),
        border: Color(light: 0xE2D8C8, dark: 0x3A352E),
        design: .serif, boldness: 0, cardRadius: 16, colorScheme: .light)

    /// Dark and private: ink, slate cards, a mint accent.
    static let vault = AppTheme(
        id: .vault, name: "Vault", summary: "Dark and private, mint accent",
        accent: Color(light: 0x5EEAD4, dark: 0x5EEAD4),
        onAccent: Color(light: 0x0E1116, dark: 0x0E1116),
        background: Color(light: 0x0E1116, dark: 0x0E1116),
        surface: Color(light: 0x171B22, dark: 0x171B22),
        border: Color(light: 0x262C36, dark: 0x262C36),
        design: .default, boldness: 1, cardRadius: 18, colorScheme: .dark)

    /// Bright and native: white cards, bold blue, heavy rounded numbers.
    /// Always light, as drawn.
    static let clarity = AppTheme(
        id: .clarity, name: "Clarity", summary: "Bright and bold, rounded numbers",
        accent: Color(light: 0x1D46D8, dark: 0x7B93FF),
        onAccent: Color(light: 0xFFFFFF, dark: 0x0B0D12),
        background: Color(light: 0xF2F3F7, dark: 0x000000),
        surface: Color(light: 0xFFFFFF, dark: 0x1C1C1E),
        border: .clear,
        design: .rounded, boldness: 1, cardRadius: 20, colorScheme: .light)

    static let all: [AppTheme] = [.ledger, .vault, .clarity]

    static func named(_ id: String) -> AppTheme {
        all.first { $0.id.rawValue == id } ?? .ledger
    }
}

/// The theme in use, kept in UserDefaults. Observable, so every view that
/// draws with `Theme` updates when it changes.
@MainActor @Observable
final class ThemeStore {
    static let shared = ThemeStore()
    static let key = "theme"

    private(set) var theme: AppTheme

    private init() {
        theme = AppTheme.named(UserDefaults.standard.string(forKey: Self.key) ?? AppTheme.ID.ledger.rawValue)
        applyToUIKit()
    }

    func select(_ id: AppTheme.ID) {
        guard id != theme.id else { return }
        theme = AppTheme.named(id.rawValue)
        UserDefaults.standard.set(id.rawValue, forKey: Self.key)
        applyToUIKit()
    }

    /// Navigation titles in the theme's typeface. Applies to bars created
    /// from now on.
    private func applyToUIKit() {
        let design: UIFontDescriptor.SystemDesign = switch theme.design {
        case .serif: .serif
        case .rounded: .rounded
        default: .default
        }
        let appearance = UINavigationBar.appearance()
        let largeWeight: UIFont.Weight = theme.boldness > 0 ? .heavy : .bold
        let large = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .largeTitle).pointSize, weight: largeWeight)
        if let descriptor = large.fontDescriptor.withDesign(design) {
            appearance.largeTitleTextAttributes = [.font: UIFont(descriptor: descriptor, size: 0)]
        }
        let inline = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .headline).pointSize, weight: .semibold)
        if let descriptor = inline.fontDescriptor.withDesign(design) {
            appearance.titleTextAttributes = [.font: UIFont(descriptor: descriptor, size: 0)]
        }
    }
}

/// The theme library: each theme as a small preview to tap.
struct ThemePicker: View {
    @Environment(AppModel.self) private var model
    private var store: ThemeStore { ThemeStore.shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(AppTheme.all) { theme in
                    Button {
                        guard theme.id == .ledger || Pro.shared.require(.themes) else { return }
                        withAnimation(.snappy) { store.select(theme.id) }
                        model.updateWidgets()
                    } label: {
                        ThemePreview(theme: theme, isSelected: store.theme.id == theme.id)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(theme.name): \(theme.summary)")
                    .accessibilityAddTraits(store.theme.id == theme.id ? .isSelected : [])
                }
                Text("Ledger and Clarity are light themes and Vault is dark, whatever your iPhone is set to.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Themes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A theme drawn small in its own colours: a total, a row and a button.
private struct ThemePreview: View {
    let theme: AppTheme
    let isSelected: Bool
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(theme.name)
                    .font(.system(.title3, design: theme.design, weight: theme.weight(.semibold)))
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? theme.accent : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("September")
                    .font(.caption)
                    .opacity(0.7)
                Text("$1,248.60")
                    .font(.system(size: 30, weight: theme.weight(.semibold), design: theme.design))
                    .monospacedDigit()
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach([0.5, 0.8, 0.65, 0.95, 0.85, 0.75], id: \.self) { height in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(height == 0.75 ? theme.accent : theme.border == .clear ? theme.accent.opacity(0.25) : theme.border)
                            .frame(height: 34 * height)
                    }
                }
                .frame(height: 34, alignment: .bottom)
                HStack {
                    Text("PG&E bill due")
                        .font(.subheadline)
                    Spacer()
                    Text("Same purchase")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(theme.accent, in: .capsule)
                }
            }
            .padding(14)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: theme.cardRadius).strokeBorder(theme.border))
            Text(theme.summary)
                .font(.footnote)
                .opacity(0.75)
        }
        .padding(16)
        .background(theme.background, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(isSelected ? theme.accent : Color.secondary.opacity(0.25),
                                                                lineWidth: isSelected ? 2.5 : 1))
        .environment(\.colorScheme, theme.colorScheme ?? systemScheme)
        .foregroundStyle(theme.colorScheme == .dark ? Color(white: 0.93) : Color.primary)
    }
}
