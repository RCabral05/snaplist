import Foundation
import UIKit

/// A plain, printable summary: a title, sections of name / detail / amount
/// rows with a total each, and a grand total. Letter size, paginated.
enum ReportPDF {
    struct Row: Sendable {
        var left: String
        var detail: String
        var right: String
    }

    struct Section: Sendable {
        var heading: String
        var rows: [Row]
        var total: String
    }

    struct Document: Sendable {
        var title: String
        var subtitle: String
        var sections: [Section]
        var grandTotal: String?
    }

    static func render(_ document: Document) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 54
        let width = page.width - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: page)

        let title: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 24, weight: .bold)]
        let subtitle: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.darkGray]
        let heading: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]
        let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11)]
        let detail: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.gray]
        let amount: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)]
        let bold: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)]

        return renderer.pdfData { context in
            var y = margin
            func newPageIfNeeded(_ needed: CGFloat) {
                if y + needed > page.height - margin {
                    context.beginPage()
                    y = margin
                }
            }
            func right(_ text: String, _ attributes: [NSAttributedString.Key: Any]) {
                let size = (text as NSString).size(withAttributes: attributes)
                (text as NSString).draw(at: CGPoint(x: margin + width - size.width, y: y), withAttributes: attributes)
            }

            context.beginPage()
            (document.title as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: title)
            y += 32
            (document.subtitle as NSString).draw(in: CGRect(x: margin, y: y, width: width, height: 30), withAttributes: subtitle)
            y += 30

            for section in document.sections {
                newPageIfNeeded(60)
                (section.heading as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: heading)
                y += 24
                for row in section.rows {
                    newPageIfNeeded(30)
                    (row.left as NSString).draw(in: CGRect(x: margin, y: y, width: width - 110, height: 14), withAttributes: body)
                    right(row.right, amount)
                    y += 14
                    if !row.detail.isEmpty {
                        (row.detail as NSString).draw(in: CGRect(x: margin, y: y, width: width - 110, height: 12), withAttributes: detail)
                        y += 12
                    }
                    y += 6
                }
                newPageIfNeeded(30)
                UIColor.lightGray.setFill()
                context.fill(CGRect(x: margin, y: y, width: width, height: 0.5))
                y += 6
                ("Total" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: bold)
                right(section.total, bold)
                y += 30
            }

            if let grandTotal = document.grandTotal {
                newPageIfNeeded(40)
                UIColor.black.setFill()
                context.fill(CGRect(x: margin, y: y, width: width, height: 1))
                y += 8
                ("Grand total" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: heading)
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)]
                right(grandTotal, attributes)
            }
        }
    }
}
