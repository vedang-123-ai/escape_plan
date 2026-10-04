// ImagePreparation.swift
// AUD-024, client half (S11.33). Import Plan used to send the photo picker's original bytes to
// /build labelled image/png. Most iPhone camera photos are HEIC and several MB, which Anthropic
// rejects with a 400; the server turned that into 502, so the user saw "AI unavailable" and
// blamed the AI. Every image now goes through here first and leaves as a real JPEG (photos) or
// PNG (a PDF page), downscaled, flattened onto white and labelled with the type it actually is.
//
// ImageIO and CoreGraphics only (no SwiftUI, no UIKit), so the whole path is unit-tested.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An image that is safe to put on the wire: its bytes are exactly `mediaType`, its long edge is
/// at most `ImagePreparation.maxLongEdge`, and its base64 form fits the server's cap. The only
/// way to make one is through `ImagePreparation`, and `APIClient.build` takes nothing else.
struct PreparedImage: Equatable {
    let data: Data
    let mediaType: String
    let pixelWidth: Int
    let pixelHeight: Int

    fileprivate init(data: Data, mediaType: String, pixelWidth: Int, pixelHeight: Int) {
        self.data = data
        self.mediaType = mediaType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

enum ImagePreparationError: Error, Equatable {
    /// The bytes are not an image ImageIO can read (or the PDF has no first page).
    case undecodable
    /// Still over the server's cap after downscaling and the lowest JPEG quality. Not reachable
    /// for a photo at 1568 px; kept so an oversized PNG fails here, not as a server 413.
    case tooLarge
}

enum ImagePreparation {
    /// Anthropic's recommended maximum long edge (vision docs): larger images are downscaled by
    /// the API anyway, so sending more only costs upload time and tokens.
    static let maxLongEdge = 1568

    /// Mirrors `MAX_IMAGE_B64_CHARS` in backend/app/limits.py (Anthropic's 10 MB base64 cap for
    /// the direct API). `ImagePreparationTests` reads that file so the two cannot drift apart.
    static let maxBase64Chars = 10_000_000

    /// JPEG qualities tried in order until the payload fits. A 1568 px photo lands well under the
    /// cap at the first one; the rest only exist so the cap is enforced rather than assumed.
    static let jpegQualities: [CGFloat] = [0.8, 0.6, 0.4]

    /// Any photo ImageIO can decode (HEIC, JPEG, PNG, a Live Photo's still) → JPEG. EXIF
    /// orientation is applied to the pixels, and no metadata (GPS included) is copied across.
    static func photo(_ data: Data) throws -> PreparedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let decoded = downscaledImage(from: source) else {
            throw ImagePreparationError.undecodable
        }
        let flat = try flattened(decoded)
        for quality in jpegQualities {
            let encoded = try encode(flat, as: .jpeg, quality: quality)
            if fits(encoded) {
                return PreparedImage(data: encoded, mediaType: "image/jpeg",
                                     pixelWidth: flat.width, pixelHeight: flat.height)
            }
        }
        throw ImagePreparationError.tooLarge
    }

    /// The first page of a PDF → PNG, long edge `maxLongEdge`. Stays PNG: a floor plan is line
    /// art, where JPEG smears the walls.
    static func pdfFirstPage(_ data: Data) throws -> PreparedImage {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else {
            throw ImagePreparationError.undecodable
        }
        let box = page.getBoxRect(.mediaBox)
        let quarterTurned = (page.rotationAngle / 90) % 2 != 0
        let pageSize = quarterTurned ? CGSize(width: box.height, height: box.width) : box.size
        guard pageSize.width > 0, pageSize.height > 0 else { throw ImagePreparationError.undecodable }
        let scale = CGFloat(maxLongEdge) / max(pageSize.width, pageSize.height)
        let width = max(1, Int((pageSize.width * scale).rounded()))
        let height = max(1, Int((pageSize.height * scale).rounded()))
        guard let context = whiteContext(width: width, height: height) else {
            throw ImagePreparationError.undecodable
        }
        // getDrawingTransform handles the page's rotation and box origin but never scales up, so
        // it maps the page onto a rect of its own size and the context does the scaling.
        context.scaleBy(x: CGFloat(width) / pageSize.width, y: CGFloat(height) / pageSize.height)
        context.concatenate(page.getDrawingTransform(.mediaBox, rect: CGRect(origin: .zero, size: pageSize),
                                                     rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let rendered = context.makeImage() else { throw ImagePreparationError.undecodable }
        let encoded = try encode(rendered, as: .png, quality: nil)
        guard fits(encoded) else { throw ImagePreparationError.tooLarge }
        return PreparedImage(data: encoded, mediaType: "image/png",
                             pixelWidth: width, pixelHeight: height)
    }

    // MARK: - Steps

    /// Decodes at most `maxLongEdge` on the long edge, orientation applied. Never upscales.
    private static func downscaledImage(from source: CGImageSource) -> CGImage? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longEdge = max(width, height)
        guard longEdge > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(longEdge, maxLongEdge),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Draws onto opaque white sRGB. JPEG has no alpha: a transparent PNG (a screenshot of a plan)
    /// would otherwise come out with a black background behind black walls.
    private static func flattened(_ image: CGImage) throws -> CGImage {
        guard let context = whiteContext(width: image.width, height: image.height) else {
            throw ImagePreparationError.undecodable
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let flat = context.makeImage() else { throw ImagePreparationError.undecodable }
        return flat
    }

    private static func whiteContext(width: Int, height: Int) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        return context
    }

    private static func encode(_ image: CGImage, as type: UTType, quality: CGFloat?) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString,
                                                                 1, nil) else {
            throw ImagePreparationError.undecodable
        }
        var options: [CFString: Any] = [:]
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImagePreparationError.undecodable }
        return output as Data
    }

    /// Base64 length is 4 * ceil(n / 3); computed rather than encoding just to measure.
    private static func fits(_ data: Data) -> Bool {
        (data.count + 2) / 3 * 4 <= maxBase64Chars
    }
}
