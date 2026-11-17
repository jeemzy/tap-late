import Foundation
import ImageIO
import UIKit
import TapLateCore

enum ImageImportError: LocalizedError {
    case invalid, tooLarge

    var errorDescription: String? {
        switch self {
        case .invalid: "This image could not be opened. Choose a PNG or JPEG screenshot and try again."
        case .tooLarge: "This image is too large. Choose a screenshot under 25 megapixels."
        }
    }
}

enum ImageImport {
    @concurrent static func normalize(_ data: Data) async throws -> CapturedImage {
        guard data.count <= 40_000_000 else { throw ImageImportError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw ImageImportError.invalid }
        guard width <= 25_000_000 / height else { throw ImageImportError.tooLarge }
        guard let image = UIImage(data: data) else { throw ImageImportError.invalid }
        let rotated = [.left, .right, .leftMirrored, .rightMirrored].contains(image.imageOrientation)
        let size = CGSize(width: rotated ? height : width, height: rotated ? width : height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: size, format: format).pngData { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return CapturedImage(data: normalized, width: Int(size.width), height: Int(size.height))
    }
}
