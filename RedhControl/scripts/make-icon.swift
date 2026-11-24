// Makes Redh Control's app icons from the artwork, Artwork/Home-Port.png: a dark teal house with an
// orange power light and a network port in it, on cream.
//
// Usage: swift scripts/make-icon.swift <artwork> <iOS output directory> [<macOS output directory>]
// Writes icon-ios-1024.png, the artwork itself; icon-ios-dark-1024.png, the house in cream with its
// orange light on transparency, for iOS's dark icons; and icon-ios-tinted-1024.png, the same in
// greys, which iOS colours. With a second directory, also the macOS icons icon-mac-16.png to
// icon-mac-1024.png: the artwork in the Mac's rounded square.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let size = 1024

guard arguments.count > 2,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fatalError("usage: swift scripts/make-icon.swift <artwork> <iOS output directory> [<macOS output directory>]")
}
let out = URL(fileURLWithPath: arguments[2])

/// The artwork's three colours, from 0 to 255: the cream around the house and in its port, the
/// house, and its light. Every pixel is one of them, or a blend of two at an edge.
let cream: SIMD3<Double> = [254, 243, 224]
let teal: SIMD3<Double> = [2, 63, 67]
let orange: SIMD3<Double> = [211, 97, 60]

func write(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("can't write \(url.path)") }
}

/// RGBA bytes, premultiplied, rows from the top.
func image(_ pixels: Int, opaque: Bool, bytes: UnsafeMutableRawPointer? = nil, draw: (CGContext) -> Void) -> CGImage {
    let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast
    let ctx = CGContext(data: bytes, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
                        space: space, bitmapInfo: alpha.rawValue)!
    ctx.interpolationQuality = .high
    draw(ctx)
    return ctx.makeImage()!
}

/// Where a colour lies on the line from `a` to `b`: the share of `b`, and how far off the line it is.
func blend(_ colour: SIMD3<Double>, _ a: SIMD3<Double>, _ b: SIMD3<Double>) -> (share: Double, distance: Double) {
    let line = b - a
    let share = min(max(((colour - a) * line).sum() / (line * line).sum(), 0), 1)
    let off = colour - (a + share * line)
    return (share, (off * off).sum().squareRoot())
}

/// The artwork with the house and its light in other colours, and the cream transparent. Each
/// pixel keeps its share of house or light, so the edges stay smooth.
func recoloured(house: SIMD3<Double>, light: SIMD3<Double>) -> CGImage {
    var input = [UInt8](repeating: 0, count: size * size * 4)
    _ = input.withUnsafeMutableBytes { bytes in
        image(size, opaque: true, bytes: bytes.baseAddress) { $0.draw(artwork, in: CGRect(x: 0, y: 0, width: size, height: size)) }
    }
    var output = [UInt8](repeating: 0, count: size * size * 4)
    for i in stride(from: 0, to: input.count, by: 4) {
        let colour = SIMD3<Double>(Double(input[i]), Double(input[i + 1]), Double(input[i + 2]))
        let wall = blend(colour, cream, teal)
        let lit = blend(colour, teal, orange)
        let (new, alpha) = lit.share > 0 && lit.distance < wall.distance
            ? (house + lit.share * (light - house), 1.0)
            : (house, wall.share)
        for channel in 0..<3 {
            output[i + channel] = UInt8((new[channel] * alpha).rounded())
        }
        output[i + 3] = UInt8((alpha * 255).rounded())
    }
    return output.withUnsafeMutableBytes { bytes in image(size, opaque: false, bytes: bytes.baseAddress) { _ in } }
}

write(image(size, opaque: true) { $0.draw(artwork, in: CGRect(x: 0, y: 0, width: size, height: size)) },
      to: out.appending(path: "icon-ios-1024.png"))
write(recoloured(house: cream, light: orange), to: out.appending(path: "icon-ios-dark-1024.png"))
// Tinted icons are grey; iOS colours them, the lighter the stronger.
write(recoloured(house: [232, 232, 232], light: [120, 120, 120]), to: out.appending(path: "icon-ios-tinted-1024.png"))

// The Mac's icons: the artwork in a rounded square of 824 by 1024 pixels, with a corner radius of
// 185, the grid Apple's macOS icons follow, and a soft shadow below it, without which the cream
// would fade into a white window. Drawn for each size rather than scaled down.
if arguments.count > 3 {
    let mac = URL(fileURLWithPath: arguments[3])
    for pixels in [16, 32, 64, 128, 256, 512, 1024] {
        let side = CGFloat(pixels)
        let inset = side * 100 / 1024
        let body = CGRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
        let radius = side * 185 / 1024
        let shape = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let icon = image(pixels, opaque: false) { ctx in
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -side * 10 / 1024), blur: side * 24 / 1024,
                          color: CGColor(gray: 0, alpha: 0.3))
            ctx.addPath(shape)
            ctx.setFillColor(CGColor(srgbRed: cream.x / 255, green: cream.y / 255, blue: cream.z / 255, alpha: 1))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.addPath(shape)
            ctx.clip()
            ctx.draw(artwork, in: body)
        }
        write(icon, to: mac.appending(path: "icon-mac-\(pixels).png"))
    }
}
