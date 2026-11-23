#if DEBUG && targetEnvironment(simulator)
import AVFoundation
import UIKit

@MainActor enum LiveSamplePages {
    static func sample(_ index: Int) -> CMReadySampleBuffer<CVReadOnlyPixelBuffer>? {
        let name = index == 0 ? "Camera" : "Tripod"
        let tint: UIColor = index == 0 ? .systemIndigo : .systemOrange
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 390, height: 810)
        let page = UIGraphicsImageRenderer(size: size, format: format).image { context in
            tint.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (index, section) in ["Shop", "Product", "Details"].enumerated() {
                let y = CGFloat(index * 270 + 25)
                (("Sample shop · " + section) as NSString).draw(at: CGPoint(x: 20, y: y),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 23), .foregroundColor: UIColor.black])
                (name as NSString).draw(at: CGPoint(x: 20, y: y + 48),
                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 72), .foregroundColor: UIColor.white])
                ((name == "Camera" ? "¥820" : "¥149") as NSString).draw(at: CGPoint(x: 20, y: y + 145),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 36), .foregroundColor: UIColor.white])
            }
        }
        guard let image = page.cgImage else { return nil }
        return LiveVideo.sample(image: image, regions: [], results: [:])
    }
}
#endif
