import AppKit
import SwiftUI
import Combine
import ServiceManagement
import UserNotifications

@main
struct BaseusMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var controller: BluetoothController!
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        controller = BluetoothController()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "Baseus Menu")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 650)
        popover.contentViewController = NSHostingController(rootView: MenuPanel(controller: controller))
        NotificationCenter.default.publisher(for: .exportBaseusDiagnostics).sink { [weak self] _ in
            self?.popover.performClose(nil)
            DispatchQueue.main.async { self?.controller.exportDiagnostics() }
        }.store(in: &subscriptions)
        controller.$state.combineLatest(controller.$connected).sink { [weak self] state, connected in
            let values = [state.left, state.right].compactMap { $0 }.filter { $0 > 0 }
            self?.statusItem.button?.title = connected ? values.min().map { " \($0)%" } ?? "" : ""
            self?.statusItem.button?.appearsDisabled = !connected
            self?.statusItem.button?.toolTip = connected ? "Baseus · sterowanie BLE połączone" : "Baseus · kliknij, aby połączyć"
        }.store(in: &subscriptions)
    }

    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Otwórz Baseus Menu", action: #selector(showPopover), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Zakończ Baseus Menu", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    @objc private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) { controller?.disconnect() }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

extension Notification.Name {
    static let exportBaseusDiagnostics = Notification.Name("pl.xmon.BaseusMenu.exportDiagnostics")
}
