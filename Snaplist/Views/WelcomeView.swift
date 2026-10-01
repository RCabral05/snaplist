import SwiftUI

/// The first thing someone sees: what Snaplist is for, the promise about
/// their data, and one obvious way in.
struct WelcomeView: View {
    let canScan: Bool
    let scan: () -> Void
    let choosePhotos: () -> Void
    let importFiles: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            PaperStack()
                .padding(.top, 24)

            VStack(spacing: 10) {
                Text("Your paper trail,\nsearchable.")
                    .font(Theme.display(.largeTitle, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Receipts, statements, warranties, manuals, and where you put things.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 18) {
                feature("doc.viewfinder", "Scan or import", "Paper, photos and PDFs. The text is read automatically.")
                feature("magnifyingglass", "Find anything", "Search a store, an amount or any word, and land on the page.")
                feature("lock.shield", "Yours alone", "Everything stays on this iPhone. No account, no uploads.")
            }
            .padding(.horizontal, 8)

            VStack(spacing: 12) {
                if canScan {
                    Button(action: scan) {
                        Label("Scan a Document", systemImage: "doc.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
                HStack(spacing: 12) {
                    Button(action: choosePhotos) {
                        Label("Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                    }
                    Button(action: importFiles) {
                        Label("Files", systemImage: "folder").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

/// Three sheets of paper, the top one with a highlighted line: the app icon's
/// idea, drawn with shapes so it follows light and dark.
private struct PaperStack: View {
    var body: some View {
        ZStack {
            sheet.rotationEffect(.degrees(-9)).offset(x: -26, y: 8).opacity(0.55)
            sheet.rotationEffect(.degrees(7)).offset(x: 24, y: 2).opacity(0.75)
            sheet.overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 9) {
                    line(54)
                    line(70)
                    line(40)
                    line(64).padding(.vertical, 3).padding(.horizontal, 4)
                        .background(Color.yellow.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
                        .padding(.horizontal, -4)
                    line(48)
                }
                .padding(16)
            }
        }
        .frame(height: 170)
        .accessibilityHidden(true)
    }

    private var sheet: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.secondarySystemGroupedBackground))
            .frame(width: 112, height: 148)
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private func line(_ width: CGFloat) -> some View {
        Capsule().fill(.secondary.opacity(0.5)).frame(width: width, height: 6)
    }
}
