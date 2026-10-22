// Draws the Tidepaper icon and writes Resources/AppIcon.icns and docs/icon.png.
// Run from the repository root: swift scripts/make-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// A filled wave across the icon body, from `baseline` down to its bottom edge.
func wave(baseline: CGFloat, amplitude: CGFloat, phase: CGFloat, in body: CGRect) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: body.minX, y: body.minY))
    for x in stride(from: body.minX, through: body.maxX, by: 2) {
        let angle = (x - body.minX) / body.width * 2 * .pi * 1.5 + phase
        path.addLine(to: CGPoint(x: x, y: baseline + amplitude * sin(angle)))
    }
    path.addLine(to: CGPoint(x: body.maxX, y: body.minY))
    path.closeSubpath()
    return path
}

/// Draws on a 1024×1024 canvas using the macOS icon grid: an 824-point rounded square with a soft shadow.
/// `scale` is the canvas-to-pixel ratio; shadows ignore the transform, so they need it explicitly.
func drawIcon(in ctx: CGContext, scale: CGFloat) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -10 * scale), blur: 24 * scale, color: color(0x000000, alpha: 0.3))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x3730A3))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // Dusk sky: deep indigo fading lighter towards the horizon.
    let sky = CGGradient(colorsSpace: sRGB, colors: [color(0x3730A3), color(0x818CF8)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: 420), options: [])

    // Sun, half set behind the far wave.
    ctx.setFillColor(color(0xFDE68A))
    ctx.fillEllipse(in: CGRect(x: 512 - 150, y: 430, width: 300, height: 300))

    // Sea: lighter far wave, deeper near wave.
    ctx.addPath(wave(baseline: 450, amplitude: 30, phase: 0.9, in: body))
    ctx.setFillColor(color(0x67E8F9))
    ctx.fillPath()

    ctx.addPath(wave(baseline: 320, amplitude: 34, phase: 2.6, in: body))
    ctx.setFillColor(color(0x0891B2))
    ctx.fillPath()
    ctx.restoreGState()
}

func writePNG(pixels: Int, to url: URL) {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(pixels) / 1024
    ctx.scaleBy(x: scale, y: scale)
    drawIcon(in: ctx, scale: scale)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}

let fileManager = FileManager.default
let iconset = fileManager.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? fileManager.removeItem(at: iconset)
try! fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    writePNG(pixels: points, to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    writePNG(pixels: points * 2, to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()

try! fileManager.createDirectory(atPath: "docs", withIntermediateDirectories: true)
writePNG(pixels: 512, to: URL(fileURLWithPath: "docs/icon.png"))
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns and docs/icon.png" : "iconutil failed")
