#!/usr/bin/env swift
// Dynamic Island app ikonunu programatik çizer: 1024px master PNG üretir.
// Kullanım: swift scripts/make-icon.swift <çıktı.png>

import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let canvas = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvas,
    pixelsHigh: canvas,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("bitmap rep oluşturulamadı")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let accent = color(0x30D158)

// --- Arka plan: macOS squircle (824pt, %10 kenar boşluğu) ---
let bgRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 186, yRadius: 186)
NSGradient(colors: [color(0x3A3A64), color(0x16161F), color(0x0A0A10)])!
    .draw(in: bgPath, angle: -90)

// Üstte hafif parlama (sheen)
bgPath.addClip()
let sheenRect = NSRect(x: 100, y: 574, width: 824, height: 350)
NSGradient(
    starting: NSColor.white.withAlphaComponent(0.10),
    ending: NSColor.white.withAlphaComponent(0)
)!.draw(in: NSBezierPath(rect: sheenRect), angle: -90)

// --- Pill altındaki yeşil ışıma (kenarı iyice yumuşak, katmanlı) ---
for (alpha, width, height, yOffset) in [
    (0.10, 760.0, 340.0, -40.0),
    (0.10, 620.0, 260.0, -20.0),
    (0.12, 480.0, 190.0, -8.0),
] {
    let glowRect = NSRect(
        x: 512 - width / 2,
        y: (520 + yOffset) - height / 2,
        width: width,
        height: height
    )
    NSGradient(
        starting: accent.withAlphaComponent(alpha),
        ending: accent.withAlphaComponent(0)
    )!.draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)
}

// --- Island pill ---
let pillRect = NSRect(x: 252, y: 476, width: 520, height: 168)
let pill = NSBezierPath(roundedRect: pillRect, xRadius: 84, yRadius: 84)
color(0x000000).setFill()
pill.fill()
NSColor.white.withAlphaComponent(0.22).setStroke()
pill.lineWidth = 4
pill.stroke()

// --- Pill içi: EQ barları + kamera noktası ---
let barHeights: [CGFloat] = [64, 108, 82, 124]
let barWidth: CGFloat = 26
let barGap: CGFloat = 16
var barX: CGFloat = 380
accent.setFill()
for height in barHeights {
    let barRect = NSRect(x: barX, y: 560 - height / 2, width: barWidth, height: height)
    NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    barX += barWidth + barGap
}

NSColor.white.withAlphaComponent(0.92).setFill()
let dotRect = NSRect(x: 612 - 30, y: 560 - 30, width: 60, height: 60)
NSBezierPath(ovalIn: dotRect).fill()
// kamera noktası içinde koyu iris
color(0x1C1C2E).setFill()
NSBezierPath(ovalIn: dotRect.insetBy(dx: 17, dy: 17)).fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("png üretilemedi")
}
try! png.write(to: URL(fileURLWithPath: outputPath))
print("✓ ikon yazıldı: \(outputPath)")
