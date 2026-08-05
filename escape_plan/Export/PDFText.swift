//  PDFText.swift
//  escape_plan — Export module
//
//  Text drawing into a raw CGContext, plus the measure-then-place helpers the page layout
//  needs to know when a block of summary text has run off the bottom of the sheet.
//
//  `UIGraphicsPushContext` is what lets UIKit's attributed-string drawing target the PDF
//  context we were handed: NSAttributedString.draw draws into UIKit's *current* context, and
//  inside a `UIGraphicsPDFRenderer` block that already is the page — but the tests rasterise
//  pages into their own bitmap contexts, where it is not. Pushing explicitly makes both work.
//
//  Print type sizes are fixed points, not Dynamic Type: paper does not resize. Dynamic Type
//  is honoured in the export sheet UI (`ExportPlanSheet`), which is the part a person reads
//  on screen.

import CoreGraphics
import Foundation
import UIKit

enum PDFText {

    /// Attributes for a plain run of text.
    static func attributes(font: UIFont, gray: CGFloat, alignment: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: font,
            .foregroundColor: UIColor(white: gray, alpha: 1),
            .paragraphStyle: paragraph,
        ]
    }

    /// Draws a single line with its top-left at `point`.
    static func draw(_ text: String, at point: CGPoint, font: UIFont, gray: CGFloat, context ctx: CGContext) {
        UIGraphicsPushContext(ctx)
        (text as NSString).draw(at: point, withAttributes: attributes(font: font, gray: gray))
        UIGraphicsPopContext()
    }

    /// Draws a single line centred (both axes) on `centre`. `background`, when given, paints a
    /// small opaque pad behind it so a label over a hatched stair or a route line stays
    /// readable in monochrome.
    static func draw(_ text: String,
                     centredAt centre: CGPoint,
                     font: UIFont,
                     gray: CGFloat,
                     background: CGFloat? = nil,
                     context ctx: CGContext) {
        let attributes = attributes(font: font, gray: gray)
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = CGPoint(x: centre.x - size.width / 2, y: centre.y - size.height / 2)
        if let background {
            ctx.saveGState()
            ctx.setFillColor(gray: background, alpha: 1)
            ctx.fill(CGRect(origin: origin, size: size).insetBy(dx: -1.5, dy: -0.5))
            ctx.restoreGState()
        }
        UIGraphicsPushContext(ctx)
        (text as NSString).draw(at: origin, withAttributes: attributes)
        UIGraphicsPopContext()
    }

    /// Height this string needs when wrapped to `width`.
    static func height(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
        let attributes = attributes(font: font, gray: 0)
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        return ceil(bounds.height)
    }

    /// Draws wrapped text into `rect` and returns the height consumed.
    @discardableResult
    static func drawWrapped(_ text: String,
                            in rect: CGRect,
                            font: UIFont,
                            gray: CGFloat,
                            context ctx: CGContext) -> CGFloat {
        UIGraphicsPushContext(ctx)
        (text as NSString).draw(with: rect,
                                options: [.usesLineFragmentOrigin, .usesFontLeading],
                                attributes: attributes(font: font, gray: gray),
                                context: nil)
        UIGraphicsPopContext()
        return height(text, width: rect.width, font: font)
    }
}
