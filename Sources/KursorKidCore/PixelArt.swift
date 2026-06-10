import CoreGraphics
import Foundation

/// Renders text pixel grids into CGImages. Each string is a row; each
/// character is one pixel; `.` (and space) are transparent.
public enum PixelArt {
    public typealias RGBA = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

    public static func image(from grid: [String], palette: [Character: RGBA]) -> CGImage? {
        guard !grid.isEmpty else { return nil }
        let width = grid.map(\.count).max() ?? 0
        let height = grid.count
        guard width > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for (y, row) in grid.enumerated() {
            for (x, ch) in row.enumerated() {
                guard ch != ".", ch != " ", let color = palette[ch] else { continue }
                let offset = (y * width + x) * 4
                pixels[offset] = color.r
                pixels[offset + 1] = color.g
                pixels[offset + 2] = color.b
                pixels[offset + 3] = color.a
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
