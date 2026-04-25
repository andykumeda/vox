#!/usr/bin/env swift
// Renders a 1024x1024 PNG AppIcon: blue→purple gradient rounded-square with
// white SF Symbol `text.bubble.fill` centered. Output: Resources/AppIcon.png.
// A subsequent `iconutil` pass builds the .icns.

import AppKit
import CoreGraphics

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
    ?? "Resources/AppIcon.png")

let size: CGFloat = 1024
let cornerRadius: CGFloat = size * 0.2237   // matches Big Sur+ app icon grid

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    fputs("failed to get graphics context\n", stderr)
    exit(1)
}

// Clip to rounded square
let rect = CGRect(x: 0, y: 0, width: size, height: size)
let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
ctx.addPath(path)
ctx.clip()

// Linear gradient: top-left to bottom-right
let colors = [
    NSColor(calibratedRed: 0.36, green: 0.43, blue: 0.95, alpha: 1).cgColor, // indigo
    NSColor(calibratedRed: 0.60, green: 0.30, blue: 0.90, alpha: 1).cgColor, // violet
    NSColor(calibratedRed: 0.85, green: 0.25, blue: 0.70, alpha: 1).cgColor, // magenta
]
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: colors as CFArray,
    locations: [0, 0.55, 1]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: []
)

// Subtle gloss: top highlight
ctx.saveGState()
let glossColors = [
    NSColor(white: 1, alpha: 0.16).cgColor,
    NSColor(white: 1, alpha: 0).cgColor,
]
let gloss = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: glossColors as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    gloss,
    start: CGPoint(x: size/2, y: size),
    end: CGPoint(x: size/2, y: size * 0.55),
    options: []
)
ctx.restoreGState()

// SF Symbol text.bubble.fill in white
let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.58, weight: .semibold)
guard let sym = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(symbolConfig) else {
    fputs("failed to load SF Symbol text.bubble.fill — need macOS 11+\n", stderr)
    exit(1)
}

let tinted = NSImage(size: sym.size)
tinted.lockFocus()
NSColor.white.set()
let symRect = NSRect(origin: .zero, size: sym.size)
symRect.fill(using: .sourceOver)
sym.draw(in: symRect, from: .zero, operation: .destinationIn, fraction: 1.0)
tinted.unlockFocus()

// Drop shadow
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.28)
shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
shadow.shadowBlurRadius = size * 0.03
shadow.set()

let symDrawSize = CGSize(width: tinted.size.width, height: tinted.size.height)
let drawRect = CGRect(
    x: (size - symDrawSize.width) / 2,
    y: (size - symDrawSize.height) / 2,
    width: symDrawSize.width,
    height: symDrawSize.height
)
tinted.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)

image.unlockFocus()

// Save PNG
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("failed to encode PNG\n", stderr)
    exit(1)
}

try? FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL)
print("wrote \(outputURL.path) (\(png.count) bytes)")
