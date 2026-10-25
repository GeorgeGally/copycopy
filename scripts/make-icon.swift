// Draws the Roger mark, a black bowtie, and writes every icon the app ships:
//   Resources/AppIcon.icns       the app icon, 16 to 1024 px, via iconutil
//   Resources/MenuBarIcon.png    the menu-bar template image at 18 pt
//   Resources/MenuBarIcon@2x.png the same at 2x
// Usage: swift scripts/make-icon.swift [output-dir]
// Nothing is read from disk: the whole mark is geometry below.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The bowtie, as fractions of the box it is drawn in. The two faces differ
/// only here: the app icon is a fuller butterfly, the menu bar a flatter,
/// wider silhouette that still reads at 18 pt.
struct Bowtie {
    var knotWidth: CGFloat      // knot width over box width
    var knotHeight: CGFloat     // knot height over box height
    var throat: CGFloat         // wing half-height where it meets the knot, over box height
    var dip: CGFloat            // how far the outer edge curves in at its middle, over box width
    var corner: CGFloat         // outer corner radius over box height

    static let icon = Bowtie(knotWidth: 0.17, knotHeight: 0.72, throat: 0.27, dip: 0.06, corner: 0.10)
    static let menuBar = Bowtie(knotWidth: 0.20, knotHeight: 0.76, throat: 0.31, dip: 0.04, corner: 0.08)

    /// The three pieces, each a closed shape, to be filled one by one: the
    /// mirrored wing winds the other way, so a single nonzero fill of all
    /// three would leave its overlap with the knot unpainted.
    func pieces(in box: CGRect) -> [CGPath] {
        let cx = box.midX, cy = box.midY, w = box.width, h = box.height
        let xi = cx + knotWidth * w * 0.3          // wing starts tucked under the knot
        let xo = cx + w / 2
        let span = xo - xi
        let top = cy + h / 2, bottom = cy - h / 2
        let ih = throat * h
        let r = corner * h
        let d = dip * w

        let wing = CGMutablePath()
        wing.move(to: CGPoint(x: xi, y: cy + ih))
        wing.addCurve(to: CGPoint(x: xo - r, y: top),
                      control1: CGPoint(x: xi + span * 0.42, y: cy + ih + (top - cy - ih) * 0.12),
                      control2: CGPoint(x: xo - r - span * 0.18, y: top - h * 0.01))
        wing.addQuadCurve(to: CGPoint(x: xo, y: top - r), control: CGPoint(x: xo, y: top))
        wing.addQuadCurve(to: CGPoint(x: xo, y: bottom + r), control: CGPoint(x: xo - d * 2, y: cy))
        wing.addQuadCurve(to: CGPoint(x: xo - r, y: bottom), control: CGPoint(x: xo, y: bottom))
        wing.addCurve(to: CGPoint(x: xi, y: cy - ih),
                      control1: CGPoint(x: xo - r - span * 0.18, y: bottom + h * 0.01),
                      control2: CGPoint(x: xi + span * 0.42, y: cy - ih - (top - cy - ih) * 0.12))
        wing.closeSubpath()

        var mirror = CGAffineTransform(translationX: cx, y: 0).scaledBy(x: -1, y: 1).translatedBy(x: -cx, y: 0)
        let other = wing.copy(using: &mirror)!

        let kw = knotWidth * w, kh = knotHeight * h
        let knot = CGRect(x: cx - kw / 2, y: cy - kh / 2, width: kw, height: kh)
        return [wing, other, CGPath(roundedRect: knot, cornerWidth: kw * 0.28, cornerHeight: kw * 0.28, transform: nil)]
    }

    func fill(in box: CGRect, _ ctx: CGContext) {
        for piece in pieces(in: box) {
            ctx.addPath(piece)
            ctx.fillPath()
        }
    }
}

let black = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [0.07, 0.07, 0.07, 1])!
let offWhite = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [0.96, 0.94, 0.90, 1])!

/// The app icon on a 1024 canvas: the tile sits on Apple's grid (824 wide
/// with a 100 margin, corners at 22.5%), the bowtie a touch above centre.
func drawAppIcon(_ ctx: CGContext) {
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let radius = tile.width * 0.225
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(offWhite)
    ctx.fillPath()

    let w = tile.width * 0.68, h = tile.height * 0.40
    let box = CGRect(x: tile.midX - w / 2, y: tile.midY + tile.height * 0.025 - h / 2, width: w, height: h)
    ctx.setFillColor(black)
    Bowtie.icon.fill(in: box, ctx)
}

/// The menu-bar mark on an 18 pt canvas: black on clear, so AppKit can tint
/// it as a template image.
func drawMenuBarIcon(_ ctx: CGContext) {
    let box = CGRect(x: 0.5, y: 4, width: 17, height: 10)
    ctx.setFillColor(black)
    Bowtie.menuBar.fill(in: box, ctx)
}

func render(pixels: Int, canvas: CGFloat, draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    draw(ctx)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write(Data("make-icon: could not write \(url.path)\n".utf8))
        exit(1)
    }
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : root.appendingPathComponent("Resources", isDirectory: true)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        writePNG(render(pixels: pixels, canvas: 1024, draw: drawAppIcon), to: iconset.appendingPathComponent(name))
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(1) }
try? FileManager.default.removeItem(at: iconset)

writePNG(render(pixels: 18, canvas: 18, draw: drawMenuBarIcon), to: output.appendingPathComponent("MenuBarIcon.png"))
writePNG(render(pixels: 36, canvas: 18, draw: drawMenuBarIcon), to: output.appendingPathComponent("MenuBarIcon@2x.png"))
print("Wrote AppIcon.icns, MenuBarIcon.png and MenuBarIcon@2x.png to \(output.path)")
