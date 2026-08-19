#!/usr/bin/swift
import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
  FileHandle.standardError.write(
    Data("Usage: render-app-icon.swift SOURCE_PNG OUTPUT_PNG\n".utf8)
  )
  exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = NSImage(contentsOf: sourceURL) else {
  FileHandle.standardError.write(Data("Could not read icon source.\n".utf8))
  exit(1)
}

let edge = 1_024
guard
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: edge,
    pixelsHigh: edge,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  )
else {
  FileHandle.standardError.write(Data("Could not create icon canvas.\n".utf8))
  exit(1)
}

bitmap.size = NSSize(width: edge, height: edge)
NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
  FileHandle.standardError.write(Data("Could not create icon graphics context.\n".utf8))
  exit(1)
}
NSGraphicsContext.current = context

let canvas = NSRect(x: 0, y: 0, width: edge, height: edge)
NSColor.clear.setFill()
canvas.fill()
NSBezierPath(roundedRect: canvas.insetBy(dx: 8, dy: 8), xRadius: 220, yRadius: 220)
  .addClip()
source.draw(
  in: canvas,
  from: .zero,
  operation: .sourceOver,
  fraction: 1,
  respectFlipped: true,
  hints: [.interpolation: NSImageInterpolation.high]
)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
  FileHandle.standardError.write(Data("Could not encode icon PNG.\n".utf8))
  exit(1)
}
try png.write(to: outputURL, options: .atomic)
