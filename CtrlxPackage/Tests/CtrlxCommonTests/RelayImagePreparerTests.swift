#if os(macOS)
    import AppKit
    import CtrlxCommon
    import ImageIO
    import Testing
    import UniformTypeIdentifiers

    /// Cross-platform image payload normalization tests.
    @Suite("Relay Image Preparer")
    struct RelayImagePreparerTests {
        @Test("Small efficient images pass through unchanged")
        func smallImagesPassThrough() throws {
            let bitmap = makeBitmap(width: 32, height: 32, noisy: false)

            for (type, format) in [
                (NSBitmapImageRep.FileType.png, ImageFormat.png),
                (.jpeg, .jpeg),
            ] {
                let data = try #require(bitmap.representation(using: type, properties: [:]))
                let original = ClipboardImage(data: data, format: format)

                let prepared = RelayImagePreparer.prepare(original, maxBytes: data.count)

                #expect(prepared == original)
            }
        }

        @Test("Raw photo data detects its format")
        func rawPhotoDataDetectsFormat() throws {
            let bitmap = makeBitmap(width: 32, height: 32, noisy: false)

            for (type, expectedFormat) in [
                (NSBitmapImageRep.FileType.png, ImageFormat.png),
                (.jpeg, .jpeg),
            ] {
                let data = try #require(bitmap.representation(using: type, properties: [:]))
                let prepared = try #require(
                    RelayImagePreparer.prepare(data, maxBytes: data.count)
                )

                #expect(prepared.data == data)
                #expect(prepared.format == expectedFormat)
            }
        }

        @Test("HEIC photo data is normalized to a compatible format")
        func heicPhotoIsNormalized() throws {
            let bitmap = makeBitmap(width: 64, height: 48, noisy: false)
            let heic = try #require(encode(bitmap, as: .heic, orientation: 6))

            let prepared = try #require(
                RelayImagePreparer.prepare(heic, maxBytes: 100 * 1_024)
            )

            #expect(prepared.format == .png || prepared.format == .jpeg)
            #expect(prepared.data.count <= 100 * 1_024)
            #expect(NSImage(data: prepared.data) != nil)
            #expect(pixelSize(of: prepared.data) == CGSize(width: 48, height: 64))
        }

        @Test("TIFF clipboard data is normalized to PNG")
        func tiffIsNormalized() throws {
            let bitmap = makeBitmap(width: 128, height: 96, noisy: false)
            let tiff = try #require(bitmap.representation(using: .tiff, properties: [:]))
            let prepared = try #require(
                RelayImagePreparer.prepare(
                    ClipboardImage(data: tiff, format: .tiff),
                    maxBytes: 100 * 1_024
                )
            )

            #expect(prepared.format == .png)
            #expect(prepared.data.count <= 100 * 1_024)
            #expect(NSImage(data: prepared.data) != nil)
        }

        @Test("Oversized PNG is compressed below the relay limit")
        func oversizedPNGIsCompressed() throws {
            let bitmap = makeBitmap(width: 512, height: 512, noisy: true)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            let maxBytes = 64 * 1_024
            #expect(png.count > maxBytes)

            let prepared = try #require(
                RelayImagePreparer.prepare(
                    ClipboardImage(data: png, format: .png),
                    maxBytes: maxBytes
                )
            )

            #expect(prepared.format == .jpeg)
            #expect(prepared.data.count <= maxBytes)
            #expect(NSImage(data: prepared.data) != nil)
        }

        @Test("Invalid oversized image is rejected")
        func invalidImageIsRejected() {
            let invalid = ClipboardImage(data: Data(repeating: 0xFF, count: 1_024), format: .png)

            #expect(RelayImagePreparer.prepare(invalid, maxBytes: 512) == nil)
            #expect(RelayImagePreparer.prepare(invalid.data, maxBytes: 512) == nil)
        }

        @Test("Image batches share one relay budget")
        func batchSharesRelayBudget() throws {
            let first = try #require(
                makeBitmap(width: 512, height: 512, noisy: true)
                    .representation(using: .png, properties: [:])
            )
            let second = try #require(
                makeBitmap(width: 480, height: 480, noisy: true)
                    .representation(using: .png, properties: [:])
            )
            let maxBytes = 512 * 1_024

            let prepared = try #require(
                RelayImagePreparer.prepareBatch(
                    [first, second],
                    maxTotalBytes: maxBytes
                )
            )

            #expect(prepared.count == 2)
            #expect(prepared.reduce(0) { $0 + $1.data.count } <= maxBytes)
            #expect(prepared.allSatisfy { NSImage(data: $0.data) != nil })
        }

        @Test("Small images leave their unused batch budget to a large image")
        func batchRedistributesUnusedBudget() throws {
            let small = try #require(
                makeBitmap(width: 128, height: 128, noisy: true)
                    .representation(using: .png, properties: [:])
            )
            let large = try #require(
                makeBitmap(width: 1_024, height: 1_024, noisy: true)
                    .representation(using: .png, properties: [:])
            )
            let maxBytes = 512 * 1_024

            let prepared = try #require(
                RelayImagePreparer.prepareBatch(
                    [small, small, small, small, large],
                    maxTotalBytes: maxBytes
                )
            )

            #expect(prepared.count == 5)
            #expect(prepared.reduce(0) { $0 + $1.data.count } <= maxBytes)
            #expect(prepared[4].data.count > maxBytes / prepared.count)
        }

        @Test("Image batches reject invalid members")
        func batchRejectsInvalidMembers() throws {
            let valid = try #require(
                makeBitmap(width: 32, height: 32, noisy: false)
                    .representation(using: .png, properties: [:])
            )

            #expect(RelayImagePreparer.prepareBatch([], maxTotalBytes: 1_024) == nil)
            #expect(
                RelayImagePreparer.prepareBatch(
                    [valid, Data(repeating: 0xFF, count: 100)],
                    maxTotalBytes: 1_024
                ) == nil
            )
        }

        private func makeBitmap(
            width: Int,
            height: Int,
            noisy: Bool
        ) -> NSBitmapImageRep {
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: width * 4,
                bitsPerPixel: 32
            )!
            let bytes = bitmap.bitmapData!
            var randomState: UInt32 = 0x1234_5678

            for offset in stride(from: 0, to: width * height * 4, by: 4) {
                if noisy {
                    randomState = 1_664_525 &* randomState &+ 1_013_904_223
                    bytes[offset] = UInt8(truncatingIfNeeded: randomState >> 24)
                    randomState = 1_664_525 &* randomState &+ 1_013_904_223
                    bytes[offset + 1] = UInt8(truncatingIfNeeded: randomState >> 24)
                    randomState = 1_664_525 &* randomState &+ 1_013_904_223
                    bytes[offset + 2] = UInt8(truncatingIfNeeded: randomState >> 24)
                } else {
                    bytes[offset] = 40
                    bytes[offset + 1] = 120
                    bytes[offset + 2] = 200
                }
                bytes[offset + 3] = 255
            }

            return bitmap
        }

        private func encode(
            _ bitmap: NSBitmapImageRep,
            as type: UTType,
            orientation: Int? = nil
        ) -> Data? {
            guard let image = bitmap.cgImage else { return nil }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output,
                type.identifier as CFString,
                1,
                nil
            ) else { return nil }
            let properties = orientation.map {
                [kCGImagePropertyOrientation: $0] as CFDictionary
            }
            CGImageDestinationAddImage(destination, image, properties)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return output as Data
        }

        private func pixelSize(of data: Data) -> CGSize? {
            guard
                let source = CGImageSourceCreateWithData(data as CFData, nil),
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                    as? [CFString: Any],
                let width = properties[kCGImagePropertyPixelWidth] as? Int,
                let height = properties[kCGImagePropertyPixelHeight] as? Int
            else { return nil }
            return CGSize(width: width, height: height)
        }
    }
#endif
