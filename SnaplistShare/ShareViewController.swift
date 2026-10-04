import UIKit
import UniformTypeIdentifiers
import WebKit

/// "Snaplist" in the share sheet: PDFs and photos are saved as they are, a
/// web page (an order confirmation in Safari) as a PDF of the page, and text
/// (a receipt email's text) as a PDF of the text. They go to the shared inbox,
/// and Snaplist reads them the next time it opens.
final class ShareViewController: UIViewController {
    private let label = UILabel()
    private var webView: WKWebView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.text = "Saving to Snaplist…"
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
        ])
        Task { await save() }
    }

    private func save() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var saved = 0
        for provider in providers {
            do {
                if try await saveFile(provider) || (try await saveWebPage(provider)) || (try await saveText(provider)) {
                    saved += 1
                }
            } catch {
                continue
            }
        }
        label.text = saved == 0 ? "Snaplist couldn't save this." : "Saved. It'll be in Snaplist the next time you open it."
        try? await Task.sleep(for: .seconds(saved == 0 ? 1.5 : 0.8))
        extensionContext?.completeRequest(returningItems: nil)
    }

    // MARK: Kinds of things shared

    /// A PDF or an image.
    private func saveFile(_ provider: NSItemProvider) async throws -> Bool {
        for type in [UTType.pdf, .image] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                    if let data { continuation.resume(returning: data) } else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
                }
            }
            let ext = type == .pdf ? "pdf" : (UTType(provider.registeredTypeIdentifiers.first ?? "")?.preferredFilenameExtension ?? "jpg")
            try write(data, ext: ext, name: provider.suggestedName)
            return true
        }
        return false
    }

    /// A web page, as Safari shares it: loaded and saved as a PDF.
    private func saveWebPage(_ provider: NSItemProvider) async throws -> Bool {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else { return false }
        let item = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
        guard let url = item as? URL, url.scheme?.hasPrefix("http") == true else { return false }
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        webView = web
        let loaded = WebLoad(web)
        web.load(URLRequest(url: url))
        try await loaded.finished()
        let pdf = try await web.pdf()
        try write(pdf, ext: "pdf", name: web.title ?? url.host())
        return true
    }

    /// Text, like a receipt email's text: set on letter pages as a PDF.
    private func saveText(_ provider: NSItemProvider) async throws -> Bool {
        guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else { return false }
        let item = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
        guard let text = item as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let attributed = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 11)])
        let data = UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            var start = 0
            repeat {
                context.beginPage()
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0),
                                                     CGPath(rect: page.insetBy(dx: 54, dy: 54), transform: nil), nil)
                let cg = context.cgContext
                cg.saveGState()
                cg.translateBy(x: 0, y: page.height)
                cg.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, cg)
                cg.restoreGState()
                let visible = CTFrameGetVisibleStringRange(frame)
                guard visible.length > 0 else { break }
                start += visible.length
            } while start < attributed.length
        }
        try write(data, ext: "pdf", name: text.split(whereSeparator: \.isNewline).first.map(String.init))
        return true
    }

    private func write(_ data: Data, ext: String, name: String?) throws {
        guard let folder = SharedInbox.folder else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The name is kept so the record starts with it; the id keeps it unique.
        let base = (name ?? "Shared").replacingOccurrences(of: "/", with: "-").prefix(60)
        try data.write(to: folder.appendingPathComponent("\(base)--\(UUID().uuidString.prefix(8)).\(ext)"), options: .atomic)
    }
}

/// Waits for a web view to finish loading.
@MainActor
private final class WebLoad: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, any Error>?
    private var done = false

    init(_ web: WKWebView) {
        super.init()
        web.navigationDelegate = self
    }

    func finished() async throws {
        if done { return }
        try await withCheckedThrowingContinuation { self.continuation = $0 }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        done = true
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        done = true
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        done = true
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
