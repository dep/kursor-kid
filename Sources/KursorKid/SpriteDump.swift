import CoreGraphics
import Foundation
import ImageIO
import KursorKidCore
import UniformTypeIdentifiers

/// Dev utility: `KursorKid --dump-sprites [dir]` renders every animation frame
/// as an 8x-scaled PNG so the art can be reviewed outside the app.
enum SpriteDump {
    static func runIfRequested() {
        guard let flagIndex = CommandLine.arguments.firstIndex(of: "--dump-sprites") else { return }
        let dir = CommandLine.arguments.count > flagIndex + 1
            ? CommandLine.arguments[flagIndex + 1]
            : "/tmp/kiki-sprites"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        for (name, frames) in KikiSprites.allAnimations.sorted(by: { $0.key < $1.key }) {
            for (i, frame) in frames.enumerated() {
                guard let image = PixelArt.image(from: frame, palette: KikiSprites.palette),
                      let scaled = upscale(image, factor: 8) else { continue }
                write(scaled, to: "\(dir)/\(name)-\(i).png")
            }
        }
        print("sprites dumped to \(dir)")
        exit(0)
    }

    private static func upscale(_ image: CGImage, factor: Int) -> CGImage? {
        let w = image.width * factor, h = image.height * factor
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .none
        // Dark backdrop so transparent pixels are distinguishable in review.
        ctx.setFillColor(CGColor(red: 0.08, green: 0.07, blue: 0.13, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    private static func write(_ image: CGImage, to path: String) {
        guard let dest = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
