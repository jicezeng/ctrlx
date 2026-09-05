#if canImport(ImageIO)
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers

    /// Converts an image into a payload that fits the relay's existing
    /// single-frame upload budget.
    public enum RelayImagePreparer {
        private static let jpegQualities: [CGFloat] = [0.9, 0.8, 0.7, 0.6, 0.5]
        private static let minimumLargestDimension = 320

        /// Prepares clipboard image data whose format is already known.
        public static func prepare(_ image: ClipboardImage, maxBytes: Int) -> ClipboardImage? {
            guard maxBytes > 0 else { return nil }

            // Preserve already-efficient clipboard representations byte-for-byte.
            // TIFF is deliberately excluded: even small TIFF payloads are poorly
            // supported by coding agents and almost always have a smaller PNG form.
            if image.format != .tiff, image.data.count <= maxBytes {
                return image
            }

            return prepareDecoded(image.data, maxBytes: maxBytes)
        }

        /// Detects the source format before preparing image bytes selected from
        /// Photos. PNG and JPEG can pass through unchanged; HEIC and other source
        /// formats are normalized so the remote Agent receives a broadly readable
        /// file extension and matching bytes.
        public static func prepare(_ data: Data, maxBytes: Int) -> ClipboardImage? {
            guard
                maxBytes > 0,
                let source = CGImageSourceCreateWithData(data as CFData, nil)
            else { return nil }

            if data.count <= maxBytes, let format = efficientFormat(of: source) {
                return ClipboardImage(data: data, format: format)
            }

            return prepare(source, maxBytes: maxBytes)
        }

        /// Prepares multiple images within one shared relay payload budget.
        ///
        /// Images first keep as much quality as the complete budget permits. If
        /// their combined size is too large, images that already fit their fair
        /// share are fixed in place. The remaining images divide the bytes those
        /// small images did not use, avoiding unnecessary quality loss while
        /// still guaranteeing the final batch fits without a second protocol.
        public static func prepareBatch(
            _ images: [Data],
            maxTotalBytes: Int
        ) -> [ClipboardImage]? {
            guard !images.isEmpty, maxTotalBytes > 0 else { return nil }

            guard let individuallyPrepared = prepare(
                images,
                maxBytesPerImage: maxTotalBytes
            ) else { return nil }
            if totalBytes(of: individuallyPrepared) <= maxTotalBytes {
                return individuallyPrepared
            }

            var result = [ClipboardImage?](repeating: nil, count: images.count)
            var remainingIndices = Array(images.indices)
            var remainingBudget = maxTotalBytes

            while !remainingIndices.isEmpty {
                let fairShare = remainingBudget / remainingIndices.count
                guard fairShare > 0 else { return nil }

                let fittingIndices = remainingIndices.filter {
                    individuallyPrepared[$0].data.count <= fairShare
                }
                guard !fittingIndices.isEmpty else {
                    for index in remainingIndices {
                        guard let image = prepare(images[index], maxBytes: fairShare) else {
                            return nil
                        }
                        result[index] = image
                    }
                    break
                }

                for index in fittingIndices {
                    let image = individuallyPrepared[index]
                    result[index] = image
                    remainingBudget -= image.data.count
                }
                let fixed = Set(fittingIndices)
                remainingIndices.removeAll { fixed.contains($0) }
            }

            let prepared = result.compactMap { $0 }
            guard
                prepared.count == images.count,
                totalBytes(of: prepared) <= maxTotalBytes
            else { return nil }
            return prepared
        }

        private static func prepare(
            _ images: [Data],
            maxBytesPerImage: Int
        ) -> [ClipboardImage]? {
            var result: [ClipboardImage] = []
            result.reserveCapacity(images.count)

            for data in images {
                guard let image = prepare(data, maxBytes: maxBytesPerImage) else {
                    return nil
                }
                result.append(image)
            }
            return result
        }

        private static func totalBytes(of images: [ClipboardImage]) -> Int {
            images.reduce(into: 0) { total, image in
                total += image.data.count
            }
        }

        private static func prepareDecoded(_ data: Data, maxBytes: Int) -> ClipboardImage? {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return nil
            }
            return prepare(source, maxBytes: maxBytes)
        }

        private static func prepare(
            _ source: CGImageSource,
            maxBytes: Int
        ) -> ClipboardImage? {
            guard let (width, height) = pixelSize(of: source) else { return nil }
            var largestDimension = max(width, height)
            guard let fullSizeImage = makeThumbnail(
                source,
                maxPixelSize: largestDimension
            ) else { return nil }

            // ImageIO's thumbnail transform applies EXIF orientation before
            // normalization. This matters for iPhone HEIC photos, whose stored
            // pixels are often landscape even when the camera view was portrait.
            if let png = encode(fullSizeImage, as: .png), png.count <= maxBytes {
                return ClipboardImage(data: png, format: .png)
            }

            var thumbnail = fullSizeImage

            while true {
                for quality in jpegQualities {
                    if let jpeg = encode(thumbnail, as: .jpeg, quality: quality),
                       jpeg.count <= maxBytes
                    {
                        return ClipboardImage(data: jpeg, format: .jpeg)
                    }
                }

                guard largestDimension > minimumLargestDimension else { return nil }
                largestDimension = max(
                    minimumLargestDimension,
                    Int(Double(largestDimension) * 0.8)
                )
                guard let resized = makeThumbnail(
                    source,
                    maxPixelSize: largestDimension
                ) else { return nil }
                thumbnail = resized
            }
        }

        private static func efficientFormat(of source: CGImageSource) -> ImageFormat? {
            guard let sourceType = CGImageSourceGetType(source) else { return nil }
            let identifier = sourceType as String
            if identifier == UTType.png.identifier { return .png }
            if identifier == UTType.jpeg.identifier { return .jpeg }
            return nil
        }

        private static func pixelSize(of source: CGImageSource) -> (width: Int, height: Int)? {
            guard
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                let width = properties[kCGImagePropertyPixelWidth] as? Int,
                let height = properties[kCGImagePropertyPixelHeight] as? Int,
                width > 0,
                height > 0
            else { return nil }

            return (width, height)
        }

        private static func makeThumbnail(
            _ source: CGImageSource,
            maxPixelSize: Int
        ) -> CGImage? {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }

        private static func encode(
            _ image: CGImage,
            as type: UTType,
            quality: CGFloat? = nil
        ) -> Data? {
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output,
                type.identifier as CFString,
                1,
                nil
            ) else { return nil }

            var properties: [CFString: Any] = [:]
            if let quality {
                properties[kCGImageDestinationLossyCompressionQuality] = quality
            }
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return output as Data
        }
    }
#endif
