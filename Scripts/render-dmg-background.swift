import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(
    Data("Usage: swift Scripts/render-dmg-background.swift OUTPUT.png\n".utf8))
  exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 680, height: 420)
guard
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0),
  let context = NSGraphicsContext(bitmapImageRep: bitmap)
else {
  FileHandle.standardError.write(Data("Could not create DMG background canvas.\n".utf8))
  exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let canvas = NSRect(origin: .zero, size: size)
let gradient = NSGradient(colors: [
  NSColor(calibratedRed: 0.035, green: 0.055, blue: 0.10, alpha: 1),
  NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.20, alpha: 1),
])
gradient?.draw(in: canvas, angle: -32)

NSColor(calibratedWhite: 1, alpha: 0.045).setStroke()
for offset in stride(from: -140.0, through: 760.0, by: 44.0) {
  let wave = NSBezierPath()
  wave.lineWidth = 1
  wave.move(to: NSPoint(x: offset, y: 30))
  wave.curve(
    to: NSPoint(x: offset + 220, y: 92),
    controlPoint1: NSPoint(x: offset + 70, y: 72),
    controlPoint2: NSPoint(x: offset + 142, y: 50))
  wave.stroke()
}

let centered = NSMutableParagraphStyle()
centered.alignment = .center

let title = NSAttributedString(
  string: "Eucrante",
  attributes: [
    .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: centered,
  ])
title.draw(in: NSRect(x: 160, y: 340, width: 360, height: 40))

let subtitle = NSAttributedString(
  string: "Drag Eucrante to Applications",
  attributes: [
    .font: NSFont.systemFont(ofSize: 15, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.72),
    .paragraphStyle: centered,
  ])
subtitle.draw(in: NSRect(x: 140, y: 310, width: 400, height: 24))

let arrow = NSBezierPath()
arrow.lineWidth = 4
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 286, y: 205))
arrow.line(to: NSPoint(x: 394, y: 205))
arrow.move(to: NSPoint(x: 378, y: 220))
arrow.line(to: NSPoint(x: 394, y: 205))
arrow.line(to: NSPoint(x: 378, y: 190))
NSColor(calibratedRed: 0.38, green: 0.78, blue: 0.96, alpha: 0.88).setStroke()
arrow.stroke()
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
  FileHandle.standardError.write(Data("Could not render DMG background.\n".utf8))
  exit(1)
}

try FileManager.default.createDirectory(
  at: outputURL.deletingLastPathComponent(),
  withIntermediateDirectories: true)
try png.write(to: outputURL, options: .atomic)
