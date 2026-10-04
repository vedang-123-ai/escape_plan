//  ImagePreparationTests.swift
//  AUD-024, client half (S11.33): whatever the photo picker hands over leaves the app as a real
//  JPEG within Anthropic's recommended size and the server's cap, and a PDF page leaves as PNG.
//  Fixtures are made at runtime with ImageIO, so no binary test files are committed. Known
//  answers throughout: exact output dimensions, the encoded format's magic bytes, and pixel
//  colours at known positions, never "the output is non-empty".

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import escape_plan

final class ImagePreparationTests: XCTestCase {

    // MARK: - Photos

    func testHEICPhotoBecomesJPEGWithinLimits() throws {
        let heic = try encodedFixture(width: 4032, height: 3024, type: "public.heic")
        let prepared = try ImagePreparation.photo(heic)
        assertJPEG(prepared, width: 1568, height: 1176)
    }

    func testLargeJPEGIsDownscaledToTheLongEdge() throws {
        let jpeg = try encodedFixture(width: 6000, height: 4500, type: UTType.jpeg.identifier)
        let prepared = try ImagePreparation.photo(jpeg)
        assertJPEG(prepared, width: 1568, height: 1176)
    }

    func testPNGPhotoBecomesJPEG() throws {
        let png = try encodedFixture(width: 2000, height: 1000, type: UTType.png.identifier)
        let prepared = try ImagePreparation.photo(png)
        assertJPEG(prepared, width: 1568, height: 784)
    }

    func testSmallPhotoIsNotUpscaled() throws {
        let jpeg = try encodedFixture(width: 800, height: 600, type: UTType.jpeg.identifier)
        let prepared = try ImagePreparation.photo(jpeg)
        assertJPEG(prepared, width: 800, height: 600)
    }

    /// A portrait iPhone photo is stored landscape with EXIF orientation 6 ("rotate 90° CW to
    /// display"). The output must be portrait and its pixels upright: the fixture's red stripe runs
    /// along the stored image's top edge, which displays as the right-hand edge.
    func testEXIFOrientationIsAppliedToThePixels() throws {
        let rotated = try encodedFixture(width: 4000, height: 3000, type: UTType.jpeg.identifier,
                                         orientation: 6, redStripeAlongTop: true)
        let prepared = try ImagePreparation.photo(rotated)
        assertJPEG(prepared, width: 1176, height: 1568)
        let pixels = try decodedPixels(prepared.data)
        XCTAssertTrue(pixels.isRed(x: pixels.width - 5, y: pixels.height / 2),
                      "the stripe should display along the right edge")
        XCTAssertFalse(pixels.isRed(x: pixels.width / 2, y: 5),
                       "the stripe must not still be along the top (orientation ignored)")
    }

    /// JPEG has no alpha. A transparent screenshot of a plan must come out white, not black.
    func testTransparencyIsFlattenedOntoWhite() throws {
        let png = try encodedFixture(width: 400, height: 300, type: UTType.png.identifier,
                                     transparent: true)
        let pixels = try decodedPixels(try ImagePreparation.photo(png).data)
        let (red, green, blue) = pixels.rgb(x: 10, y: 10)
        XCTAssertGreaterThan(min(red, green, blue), 240, "transparent area should flatten to white")
    }

    func testUndecodableBytesAreRejected() {
        XCTAssertThrowsError(try ImagePreparation.photo(Data("not an image".utf8))) { error in
            XCTAssertEqual(error as? ImagePreparationError, .undecodable)
        }
        XCTAssertThrowsError(try ImagePreparation.photo(Data())) { error in
            XCTAssertEqual(error as? ImagePreparationError, .undecodable)
        }
    }

    /// The client cap must equal the server's, or a photo the app thinks is fine is refused.
    func testSizeCapMirrorsTheServer() throws {
        let limits = try String(contentsOf: repoRoot().appendingPathComponent("backend/app/limits.py"),
                                encoding: .utf8)
        let line = try XCTUnwrap(limits.split(separator: "\n")
            .first { $0.hasPrefix("MAX_IMAGE_B64_CHARS = ") })
        let server = Int(line.dropFirst("MAX_IMAGE_B64_CHARS = ".count).replacingOccurrences(of: "_", with: ""))
        XCTAssertEqual(server, ImagePreparation.maxBase64Chars)
    }

    // MARK: - PDF

    /// A US Letter page whose bottom-left quadrant is black. PDF space has its origin bottom-left,
    /// so in the rendered image (origin top-left) black sits at the bottom-left, white at the top.
    func testPDFPageBecomesUprightPNGAtTheLongEdge() throws {
        let prepared = try ImagePreparation.pdfFirstPage(try pdfFixture(width: 612, height: 792))
        XCTAssertEqual(prepared.mediaType, "image/png")
        XCTAssertEqual(Array(prepared.data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertEqual(prepared.pixelHeight, 1568)
        XCTAssertEqual(prepared.pixelWidth, 1212)
        let pixels = try decodedPixels(prepared.data)
        XCTAssertEqual(pixels.width, 1212)
        XCTAssertEqual(pixels.height, 1568)
        XCTAssertLessThan(pixels.rgb(x: 50, y: pixels.height - 50).0, 30, "bottom-left should be black")
        XCTAssertGreaterThan(pixels.rgb(x: 50, y: 50).0, 225, "top-left should be white")
        // Just inside the quadrant's inner corner: black only if the page was scaled to fill the
        // image, not drawn at 1 pt = 1 px in the corner.
        XCTAssertLessThan(pixels.rgb(x: pixels.width * 45 / 100, y: pixels.height * 55 / 100).0, 30,
                          "the page must be scaled up to the long edge")
        XCTAssertGreaterThan(pixels.rgb(x: pixels.width * 55 / 100, y: pixels.height * 55 / 100).0, 225)
    }

    func testNotAPDFIsRejected() {
        XCTAssertThrowsError(try ImagePreparation.pdfFirstPage(Data("%PDF-nope".utf8))) { error in
            XCTAssertEqual(error as? ImagePreparationError, .undecodable)
        }
    }

    // MARK: - Assertions

    private func assertJPEG(_ prepared: PreparedImage, width: Int, height: Int,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(prepared.mediaType, "image/jpeg", file: file, line: line)
        XCTAssertEqual(Array(prepared.data.prefix(3)), [0xFF, 0xD8, 0xFF], "JPEG magic", file: file, line: line)
        XCTAssertEqual(prepared.pixelWidth, width, file: file, line: line)
        XCTAssertEqual(prepared.pixelHeight, height, file: file, line: line)
        XCTAssertLessThanOrEqual(max(prepared.pixelWidth, prepared.pixelHeight),
                                 ImagePreparation.maxLongEdge, file: file, line: line)
        XCTAssertLessThanOrEqual(prepared.data.base64EncodedString().count,
                                 ImagePreparation.maxBase64Chars, file: file, line: line)
        // What the decoder sees must match what the struct claims.
        if let source = CGImageSourceCreateWithData(prepared.data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, width, file: file, line: line)
            XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, height, file: file, line: line)
            XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier,
                           file: file, line: line)
        } else {
            XCTFail("output does not decode", file: file, line: line)
        }
    }
}

// MARK: - Fixtures (shared with BuildRequestEncodingTests)

/// Encodes a noisy photo-like image of the given size. Noise keeps the JPEG realistically large
/// (a flat colour would compress to nothing and prove nothing about the size cap).
/// HEIC encoding is not available on every simulator; the test is skipped, not passed, then.
func encodedFixture(width: Int, height: Int, type: String, orientation: Int? = nil,
                    redStripeAlongTop: Bool = false, transparent: Bool = false) throws -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if !transparent {
        var generator = SystemRandomNumberGenerator()
        let tile = 16
        for ty in stride(from: 0, to: height, by: tile) {
            for tx in stride(from: 0, to: width, by: tile) {
                let grey = CGFloat(UInt8.random(in: 60...200, using: &generator)) / 255
                context.setFillColor(CGColor(srgbRed: grey, green: grey * 0.9, blue: grey * 0.8, alpha: 1))
                context.fill(CGRect(x: tx, y: ty, width: tile, height: tile))
            }
        }
    }
    if redStripeAlongTop {
        // CGContext's origin is bottom-left, so the stored image's top edge is y near height.
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height - 200, width: width, height: 200))
    }
    let image = context.makeImage()!
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, type as CFString, 1, nil) else {
        throw XCTSkip("This simulator cannot encode \(type); see BLOCKERS S11.33.")
    }
    var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.95]
    if let orientation { properties[kCGImagePropertyOrientation] = orientation }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw XCTSkip("This simulator cannot encode \(type); see BLOCKERS S11.33.")
    }
    return output as Data
}

/// A one-page PDF of the given size in points, bottom-left quadrant filled black.
func pdfFixture(width: CGFloat, height: CGFloat) throws -> Data {
    let output = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: width, height: height)
    let consumer = try XCTUnwrap(CGDataConsumer(data: output))
    let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
    context.beginPDFPage(nil)
    context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
    context.endPDFPage()
    context.closePDF()
    return output as Data
}

struct DecodedPixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    /// Top-left origin, as the image displays.
    func rgb(x: Int, y: Int) -> (Int, Int, Int) {
        let index = (y * width + x) * 4
        return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]))
    }

    func isRed(x: Int, y: Int) -> Bool {
        let (red, green, blue) = rgb(x: x, y: y)
        return red > 200 && green < 60 && blue < 60
    }
}

func decodedPixels(_ data: Data) throws -> DecodedPixels {
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return true
    }
    XCTAssertTrue(drawn, "could not draw the decoded image")
    return DecodedPixels(width: image.width, height: image.height, bytes: bytes)
}

func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
}
