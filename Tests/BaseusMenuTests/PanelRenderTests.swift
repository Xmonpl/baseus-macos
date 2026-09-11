import XCTest
import SwiftUI
import AppKit
@testable import BaseusMenu

final class PanelRenderTests: XCTestCase {
    @MainActor
    func testRenderConnectedAndDisconnectedPanels() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/previews")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for connected in [true, false] {
            for dark in [true, false] {
                let controller = BluetoothController(previewConnected: connected)
                let panel = MenuPanel(controller: controller).environment(\.colorScheme, dark ? .dark : .light)
                let view = NSHostingView(rootView: panel)
                view.frame = NSRect(x: 0, y: 0, width: 380, height: 650)
                view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = view
                view.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                XCTAssertGreaterThan(data.count, 5000)
                try data.write(to: directory.appendingPathComponent("\(connected ? "connected" : "disconnected")-\(dark ? "dark" : "light").png"))
                // Window is never ordered on screen or activated.
                window.contentView = nil
            }
        }
    }
}
