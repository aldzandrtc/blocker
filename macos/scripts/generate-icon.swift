#!/usr/bin/env swift
import AppKit
import Foundation

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath

let shield = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { rect in
    NSColor(red: 0.25, green: 0.30, blue: 0.95, alpha: 1.0).setFill()
    let path = NSBezierPath(roundedRect: rect, xRadius: 160, yRadius: 160)
    path.fill()

    if let sym = NSImage(systemSymbolName: "shield.fill",
                         accessibilityDescription: nil) {
        let cfg = NSImage.SymbolConfiguration(pointSize: 520, weight: .bold)
        let colored = sym.withSymbolConfiguration(cfg)!
        let symSize = colored.size
        let x = (1024 - symSize.width) / 2
        let y = (1024 - symSize.height) / 2
        colored.draw(in: NSRect(x: x, y: y,
                                width: symSize.width, height: symSize.height))
    }
    return true
}

let iconset = "\(outDir)/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try FileManager.default.createDirectory(atPath: iconset,
                                        withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

func resize(_ image: NSImage, to size: NSSize) -> NSImage {
    let r = NSImage(size: size, flipped: false) { rect in
        image.draw(in: rect)
        return true
    }
    return r
}

for (sz, name) in sizes {
    let s = NSSize(width: sz, height: sz)
    let resized = resize(shield, to: s)
    guard let tiff = resized.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { continue }
    try png.write(to: URL(fileURLWithPath: "\(iconset)/\(name)"))
}

// Run iconutil
let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconset, "-o", "\(outDir)/AppIcon.icns"]
task.launch()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("AppIcon.icns generated at \(outDir)/AppIcon.icns")
} else {
    print("iconutil failed with exit code \(task.terminationStatus)")
    exit(1)
}
