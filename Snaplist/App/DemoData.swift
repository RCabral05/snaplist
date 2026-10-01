import ArchiveCore
import SwiftUI
import UIKit

/// Sample records for screenshots and UI tests, enabled by the `-demoData`
/// launch argument. Debug builds only; TestFlight and App Store builds are
/// Release and don't contain this.
///
/// The documents are drawn as images (and one PDF) so they go through the real
/// pipeline: Vision reads the images, PDFKit reads the PDF's text layer.
#if DEBUG
enum DemoData {
    /// A throwaway archive and no lock: `-demoData` fills it, `-demoEmpty`
    /// leaves it empty to show the welcome screen.
    static var isEnabled: Bool {
        shouldSeed || ProcessInfo.processInfo.arguments.contains("-demoEmpty")
    }

    /// `-forceDark` / `-forceLight`, since the simulator's own appearance
    /// switch doesn't reliably reach a test run.
    static var forcedColorScheme: ColorScheme? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-forceDark") { return .dark }
        if arguments.contains("-forceLight") { return .light }
        return nil
    }

    static var shouldSeed: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoData")
    }

    @MainActor
    static func seed(into model: AppModel) {
        let day: TimeInterval = 86_400
        let now = Date.now

        model.add(kind: .statement, title: "Chase Visa · September",
                  items: [pdf(pages: [statementPage1, statementPage2])], at: now - 1 * day)
        model.add(kind: .receipt, title: "Shell",
                  items: [image(receipt(shell))], at: now - 2 * day)
        model.add(kind: .receipt, title: "Costco",
                  items: [image(receipt(costco))], at: now - 5 * day)
        model.add(kind: .item, title: "Spare HDMI cable · hall closet, top shelf",
                  items: [image(label(["HDMI 2.1 CABLE", "8K @ 60Hz · 6 FT", "BOX 3 · HALL CLOSET"]))], at: now - 9 * day)
        model.add(kind: .receipt, title: "Trader Joe's",
                  items: [image(receipt(traderJoes))], at: now - 12 * day)
        model.add(kind: .bill, title: "PG&E · August",
                  items: [image(receipt(pge, width: 1000))], at: now - 33 * day)
        model.add(kind: .warranty, title: "Samsung TV warranty",
                  items: [image(receipt(samsung, width: 1000))], at: now - 160 * day)
    }

    // MARK: Content

    static let shell = [
        "SHELL", "1234 MAIN ST", "SAN JOSE CA 95112", "",
        "09/28/2026  08:14", "PUMP 6", "",
        "UNLEADED     10.214 GAL", "PRICE/GAL         3.899", "",
        "FUEL TOTAL      $39.82", "",
        "VISA ************4421", "AUTH 0193AB", "THANK YOU",
    ]

    static let costco = [
        "COSTCO WHOLESALE", "SAN JOSE #423", "", "09/25/2026 17:42", "",
        "KS PAPER TOWEL      21.99", "AA BATTERIES 48     17.49", "ROTISSERIE CHKN      4.99",
        "ORGANIC EGGS 24      8.79", "OLIVE OIL 2L        15.99", "",
        "SUBTOTAL            69.25", "TAX                  3.40", "TOTAL               72.65", "",
        "VISA ****4421", "ITEMS SOLD 5",
    ]

    static let traderJoes = [
        "TRADER JOE'S", "STORE #231", "", "09/18/2026", "",
        "BANANAS              0.95", "GREEK YOGURT         5.49", "COFFEE BEANS        10.99",
        "FROZEN GYOZA         4.29", "", "TOTAL               21.72", "", "VISA ****4421",
    ]

    static let pge = [
        "PG&E", "ENERGY STATEMENT", "", "ACCOUNT 0123456789-0", "STATEMENT DATE 08/29/2026",
        "SERVICE 07/28/2026 - 08/26/2026", "", "ELECTRIC CHARGES     $142.37", "GAS CHARGES           $18.06",
        "", "TOTAL AMOUNT DUE     $160.43", "DUE DATE 09/19/2026",
    ]

    static let samsung = [
        "SAMSUNG", "LIMITED WARRANTY", "", "MODEL QN65Q80D", "SERIAL 0A1B2C3D4E",
        "PURCHASED 04/14/2026", "BEST BUY #112", "",
        "COVERAGE: 1 YEAR PARTS AND LABOR", "PANEL: 2 YEARS", "", "EXPIRES 04/14/2027",
        "1-800-SAMSUNG",
    ]

    static let statementPage1 = [
        "CHASE", "Freedom Visa Statement", "Account ending 4421",
        "Statement period 08/29/2026 - 09/28/2026", "",
        "Previous balance                $412.08", "Payments                       -$412.08",
        "Purchases                        $826.31", "New balance                      $826.31",
        "Payment due date 10/23/2026",
    ]

    static let statementPage2 = [
        "Transactions", "",
        "09/02  PG&E WEB ONLINE              160.43", "09/05  SHELL OIL 57442               44.10",
        "09/18  TRADER JOE'S #231             21.72", "09/20  NETFLIX.COM                   15.49",
        "09/25  COSTCO WHSE #423              72.65", "09/28  SHELL OIL 57442               39.82",
        "09/28  AMAZON MKTPL                 472.10",
    ]

    // MARK: Drawing

    static func image(_ image: UIImage) -> ImportItem {
        ImportItem(type: .image, source: .data(image.jpegData(compressionQuality: 0.9)!), fileExtension: "jpg")
    }

    /// A paper slip on a dark surface, like a photo of a receipt on a table.
    static func receipt(_ lines: [String], width: CGFloat = 820) -> UIImage {
        let lineHeight: CGFloat = 46
        let paper = CGRect(x: 90, y: 90, width: width, height: CGFloat(lines.count) * lineHeight + 140)
        let size = CGSize(width: paper.maxX + 90, height: paper.maxY + 90)
        let font = UIFont.monospacedSystemFont(ofSize: 30, weight: .medium)

        return render(size) { context in
            UIColor(white: 0.16, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1).setFill()
            UIBezierPath(roundedRect: paper, cornerRadius: 6).fill()

            for (index, line) in lines.enumerated() {
                let text = NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: UIColor(white: 0.12, alpha: 1)])
                let x = index < 3 ? paper.midX - text.size().width / 2 : paper.minX + 60
                text.draw(at: CGPoint(x: x, y: paper.minY + 70 + CGFloat(index) * lineHeight))
            }
        }
    }

    /// A printed label on cardboard, like a photo of a box.
    static func label(_ lines: [String]) -> UIImage {
        let size = CGSize(width: 1000, height: 1000)
        let tag = CGRect(x: 160, y: 300, width: 680, height: 400)
        return render(size) { context in
            UIColor(red: 0.72, green: 0.56, blue: 0.38, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            UIBezierPath(roundedRect: tag, cornerRadius: 10).fill()
            for (index, line) in lines.enumerated() {
                let font = UIFont.systemFont(ofSize: index == 0 ? 56 : 38, weight: index == 0 ? .heavy : .semibold)
                let text = NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: UIColor.black])
                text.draw(at: CGPoint(x: tag.midX - text.size().width / 2, y: tag.minY + 70 + CGFloat(index) * 100))
            }
        }
    }

    /// A US Letter PDF with a real text layer, one page per entry.
    static func pdf(pages: [[String]]) -> ImportItem {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for lines in pages {
                context.beginPage()
                for (index, line) in lines.enumerated() {
                    let font = index == 0 ? UIFont.boldSystemFont(ofSize: 22) : UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                    NSAttributedString(string: line, attributes: [.font: font])
                        .draw(at: CGPoint(x: 56, y: 60 + CGFloat(index) * 24))
                }
            }
        }
        return ImportItem(type: .pdf, source: .data(data), fileExtension: "pdf")
    }

    private static func render(_ size: CGSize, _ draw: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image(actions: draw)
    }
}
#else
/// Release builds: no demo data, the system's appearance.
enum DemoData {
    static let forcedColorScheme: ColorScheme? = nil
}
#endif
