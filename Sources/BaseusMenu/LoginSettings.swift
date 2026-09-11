import Foundation
import Combine
import ServiceManagement

enum LoginServiceState { case enabled, needsApproval, disabled }

protocol LoginService {
    var state: LoginServiceState { get }
    func register() throws
    func unregister() throws
}

struct SystemLoginService: LoginService {
    var state: LoginServiceState {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .needsApproval
        default: return .disabled
        }
    }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

/// Compatibility path for local/ad-hoc builds rejected by ServiceManagement with
/// EINVAL. A per-user RunAtLoad job launches the app once at login via LaunchServices.
/// There is no KeepAlive, helper daemon, shell interpolation or periodic execution.
struct LoginAgentStore {
    static let label = "pl.xmon.BaseusMenu.login"
    let file: URL
    let app: URL
    var exists: Bool { FileManager.default.fileExists(atPath: file.path) }

    init(file: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(Self.label).plist"),
         app: URL = Bundle.main.bundleURL) {
        self.file = file
        self.app = app.standardizedFileURL
    }

    func enable() throws {
        guard app.pathExtension == "app", !app.path.contains("/AppTranslocation/"),
              let executable = Bundle(url: app)?.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw NSError(domain: "BaseusLogin", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Przenieś Baseus Menu.app do Applications i uruchom tę kopię ponownie przed włączeniem autostartu."])
        }
        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": ["/usr/bin/open", "-g", "-a", app.path],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "AssociatedBundleIdentifiers": ["pl.xmon.BaseusMenu"]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
    }

    func disable() throws {
        if exists { try FileManager.default.removeItem(at: file) }
        // No bootstrap is performed at registration: launchd reads this file at
        // the next login. Removing it disables future logins without killing the app.
    }
}

final class LoginSettings: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var usesCompatibility = false
    @Published var error: String?
    private let service: LoginService
    private let store: LoginAgentStore

    init(service: LoginService = SystemLoginService(), store: LoginAgentStore = LoginAgentStore()) {
        self.service = service
        self.store = store
        // Repair the absolute path after the user moves an already opted-in app.
        if store.exists {
            do { try store.enable() } catch { self.error = error.localizedDescription }
        }
        refresh()
    }

    func refresh() {
        usesCompatibility = store.exists
        requiresApproval = service.state == .needsApproval
        enabled = usesCompatibility || service.state != .disabled
    }

    func setEnabled(_ value: Bool) {
        error = nil
        do {
            if value {
                if store.exists { try store.enable() }
                else {
                    do { try service.register() }
                    catch {
                        guard Self.isInvalidArgument(error as NSError), service.state == .disabled else { throw error }
                        try store.enable()
                    }
                }
            } else {
                if service.state != .disabled { try service.unregister() }
                try store.disable()
            }
        } catch { self.error = error.localizedDescription }
        refresh()
    }

    static func isInvalidArgument(_ error: NSError) -> Bool {
        if error.code == 22 && [NSPOSIXErrorDomain, "SMAppServiceErrorDomain"].contains(error.domain) { return true }
        return (error.userInfo[NSUnderlyingErrorKey] as? NSError).map(isInvalidArgument) ?? false
    }
}
