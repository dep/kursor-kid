import CoreGraphics
import Foundation
import ImageIO
import KursorKidCore
import UniformTypeIdentifiers

/// Dev utility: `KursorKid --dump-sprites [dir]` renders every animation frame
/// as an 8x-scaled PNG so the art can be reviewed outside the app.
enum SpriteDump {
    static func runIfRequested() {
        dumpIconIfRequested()
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

    /// `--dump-icon <path>` renders a 1024×1024 app icon (Kiki on a dark
    /// rounded square) for icns generation.
    private static func dumpIconIfRequested() {
        guard let flagIndex = CommandLine.arguments.firstIndex(of: "--dump-icon"),
              CommandLine.arguments.count > flagIndex + 1 else { return }
        let path = CommandLine.arguments[flagIndex + 1]
        let canvas = 1024
        guard let sprite = PixelArt.image(from: KikiSprites.idle[0], palette: KikiSprites.palette),
              let ctx = CGContext(
                  data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return }
        ctx.interpolationQuality = .none
        // macOS-style rounded-square background.
        let inset: CGFloat = 100
        let rect = CGRect(x: inset, y: inset, width: CGFloat(canvas) - inset * 2, height: CGFloat(canvas) - inset * 2)
        let rounded = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
        ctx.addPath(rounded)
        ctx.setFillColor(CGColor(red: 0.08, green: 0.07, blue: 0.13, alpha: 1))
        ctx.fillPath()
        // Kiki centered, snapped to whole-pixel scale for crispness.
        let scale: CGFloat = 34
        let w = CGFloat(sprite.width) * scale
        let h = CGFloat(sprite.height) * scale
        ctx.draw(sprite, in: CGRect(x: (CGFloat(canvas) - w) / 2, y: (CGFloat(canvas) - h) / 2, width: w, height: h))
        if let image = ctx.makeImage() {
            write(image, to: path)
            print("icon written to \(path)")
        }
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
