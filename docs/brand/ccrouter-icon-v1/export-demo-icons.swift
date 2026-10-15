#!/usr/bin/env swift
// Run on macOS: swift docs/brand/ccrouter-icon-v1/export-demo-icons.swift
// Uses the SVG master and system frameworks; no Flutter/Pub dependencies.
import AppKit
import ImageIO

let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let root = assets.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let demo = root.appendingPathComponent("demo")
guard let image = NSImage(contentsOf: assets.appendingPathComponent("ccrouter-icon-dark.svg")),
      let master = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Could not render the SVG master")
}

var exported = 0
func export(_ url: URL, size: Int, opaque: Bool, scale: Double = 1) throws {
    let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    guard let context = CGContext(data: nil, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: alpha.rawValue) else {
        fatalError("Cannot allocate image context")
    }
    if opaque {
        context.setFillColor(CGColor(srgbRed: 16 / 255, green: 26 / 255, blue: 48 / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }
    context.interpolationQuality = .high
    let edge = Double(size) * scale
    let inset = (Double(size) - edge) / 2
    context.draw(master, in: CGRect(x: inset, y: inset, width: edge, height: edge))
    guard let output = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("Cannot encode \(url.path)")
    }
    CGImageDestinationAddImage(destination, output, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write \(url.path)") }
    exported += 1
}

struct Catalog: Decodable {
    struct Entry: Decodable { let filename: String; let size: String; let scale: String }
    let images: [Entry]
}
for platform in ["ios", "macos"] {
    let folder = demo.appendingPathComponent("\(platform)/Runner/Assets.xcassets/AppIcon.appiconset")
    let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: folder.appendingPathComponent("Contents.json")))
    var written = Set<String>()
    for entry in catalog.images where written.insert(entry.filename).inserted {
        let size = Int(Double(entry.size.split(separator: "x")[0])! * Double(entry.scale.dropLast())!)
        try export(folder.appendingPathComponent(entry.filename), size: size,
                   opaque: platform == "ios", scale: platform == "macos" ? 0.86 : 1)
    }
}
for (density, size) in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)] {
    try export(demo.appendingPathComponent("android/app/src/main/res/mipmap-\(density)/ic_launcher.png"),
               size: size, opaque: false)
}
for relative in ["AppScope/resources/base/media/app_icon.png",
                 "entry/src/main/resources/base/media/icon.png",
                 "entry/src/ohosTest/resources/base/media/icon.png"] {
    try export(demo.appendingPathComponent("ohos/\(relative)"), size: 512, opaque: true)
}
for size in [192, 512] {
    try export(demo.appendingPathComponent("web/icons/Icon-\(size).png"), size: size, opaque: true)
    // 90% scale keeps even the mark's bounding-box corners inside the
    // maskable icon's central circle (radius = 40% of the canvas).
    try export(demo.appendingPathComponent("web/icons/Icon-maskable-\(size).png"), size: size, opaque: true, scale: 0.9)
}
try export(demo.appendingPathComponent("web/favicon.png"), size: 32, opaque: false)
for size in [32, 64, 256, 1024] {
    try export(assets.appendingPathComponent("ccrouter-icon-\(size).png"), size: size, opaque: false)
}
print("Exported \(exported) Demo and brand icon assets from ccrouter-icon-dark.svg")
