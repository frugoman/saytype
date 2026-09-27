// Renders the SayType app icon. Usage: swift make_icon.swift <out.png> [size]
import AppKit

let out = CommandLine.arguments[1]
let S = CGFloat(Double(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "1024")!)
let k = S / 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

// macOS icon grid: 824pt body centered in 1024 with ~185pt corner radius.
let body = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
let shape = CGPath(roundedRect: body, cornerWidth: 186 * k, cornerHeight: 186 * k, transform: nil)

// Soft drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 28 * k, color: c(0x000000, 0.35))
ctx.addPath(shape); ctx.setFillColor(c(0x1B1440)); ctx.fillPath()
ctx.restoreGState()

// Background gradient
ctx.saveGState()
ctx.addPath(shape); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [c(0x7B5CFF), c(0x3A2BD6), c(0x16106B)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 180 * k, y: 924 * k), end: CGPoint(x: 850 * k, y: 100 * k), options: [])
// Top sheen
let sheen = CGGradient(colorsSpace: cs, colors: [c(0xFFFFFF, 0.22), c(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: 360 * k, y: 860 * k), startRadius: 0,
                       endCenter: CGPoint(x: 360 * k, y: 860 * k), endRadius: 620 * k, options: [])
// Glow behind the caret
let glow = CGGradient(colorsSpace: cs, colors: [c(0x52F5C8, 0.45), c(0x52F5C8, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 735 * k, y: 512 * k), startRadius: 0,
                       endCenter: CGPoint(x: 735 * k, y: 512 * k), endRadius: 260 * k, options: [])
ctx.restoreGState()

// Waveform bars: voice, growing more solid as it approaches the cursor.
let heights: [CGFloat] = [120, 250, 380, 250, 170]
let barW: CGFloat = 52, gap: CGFloat = 30
var x: CGFloat = 225
for (i, h) in heights.enumerated() {
    let r = CGRect(x: x * k, y: (512 - h / 2) * k, width: barW * k, height: h * k)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: barW / 2 * k, cornerHeight: barW / 2 * k, transform: nil))
    ctx.setFillColor(c(0xFFFFFF, 0.55 + 0.45 * CGFloat(i) / CGFloat(heights.count - 1)))
    ctx.fillPath()
    x += barW + gap
}

// Text caret (I-beam): the typed result.
let caretX: CGFloat = 735, caretH: CGFloat = 470, stem: CGFloat = 44, serif: CGFloat = 150, serifH: CGFloat = 40
ctx.setFillColor(c(0x52F5C8))
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 24 * k, color: c(0x52F5C8, 0.8))
let stemRect = CGRect(x: (caretX - stem / 2) * k, y: (512 - caretH / 2) * k, width: stem * k, height: caretH * k)
ctx.addPath(CGPath(roundedRect: stemRect, cornerWidth: stem / 2 * k, cornerHeight: stem / 2 * k, transform: nil))
for y in [512 + caretH / 2 - serifH, 512 - caretH / 2] {
    let r = CGRect(x: (caretX - serif / 2) * k, y: y * k, width: serif * k, height: serifH * k)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: serifH / 2 * k, cornerHeight: serifH / 2 * k, transform: nil))
}
ctx.fillPath()
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
