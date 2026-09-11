import AppKit

// A code-drawn application icon; no remote assets or build dependencies.
let output = CommandLine.arguments[1]
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        NSColor(calibratedRed: 0.98, green: 0.79, blue: 0.15, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.06, y: p * 0.06, width: p * 0.88, height: p * 0.88), xRadius: p * 0.20, yRadius: p * 0.20).fill()
        let path = NSBezierPath()
        path.lineWidth = p * 0.07
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: p * 0.28, y: p * 0.39))
        path.line(to: NSPoint(x: p * 0.28, y: p * 0.55))
        path.curve(to: NSPoint(x: p * 0.72, y: p * 0.55), controlPoint1: NSPoint(x: p * 0.28, y: p * 0.84), controlPoint2: NSPoint(x: p * 0.72, y: p * 0.84))
        path.line(to: NSPoint(x: p * 0.72, y: p * 0.39))
        NSColor(calibratedWhite: 0.10, alpha: 1).setStroke()
        path.stroke()
        NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
        for x in [0.23, 0.63] {
            NSBezierPath(roundedRect: NSRect(x: p * x, y: p * 0.28, width: p * 0.14, height: p * 0.26), xRadius: p * 0.06, yRadius: p * 0.06).fill()
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = bitmap.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", directory.path, "-o", output]
try task.run()
task.waitUntilExit()
exit(task.terminationStatus)
