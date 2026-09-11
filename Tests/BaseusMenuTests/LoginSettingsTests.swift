import XCTest
@testable import BaseusMenu

private final class FakeLoginService: LoginService {
    var state: LoginServiceState = .disabled
    var failure: Error?
    var registrations = 0
    func register() throws {
        registrations += 1
        if let failure { throw failure }
        state = .enabled
    }
    func unregister() throws { state = .disabled }
}

final class LoginSettingsTests: XCTestCase {
    private var directory: URL!
    private var app: URL!
    private var store: LoginAgentStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        app = directory.appendingPathComponent("Aplikacja ze spacją & znakiem $.app")
        let macos = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleExecutable": "Test", "CFBundleIdentifier": "pl.xmon.BaseusMenu", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let binary = macos.appendingPathComponent("Test")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        store = LoginAgentStore(file: directory.appendingPathComponent("LaunchAgents/login.plist"), app: app)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testInvalidArgumentCreatesValidUserAgentAndDisableRemovesIt() throws {
        let service = FakeLoginService()
        service.failure = NSError(domain: "SMAppServiceErrorDomain", code: 22)
        let settings = LoginSettings(service: service, store: store)
        settings.setEnabled(true)
        XCTAssertNil(settings.error)
        XCTAssertTrue(settings.enabled)
        XCTAssertTrue(settings.usesCompatibility)
        let data = try Data(contentsOf: store.file)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["ProgramArguments"] as? [String], ["/usr/bin/open", "-g", "-a", app.path])
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertNil(plist["KeepAlive"])
        settings.setEnabled(false)
        XCTAssertFalse(settings.enabled)
        XCTAssertFalse(store.exists)
    }

    func testSuccessfulNativeRegistrationDoesNotCreateSecondLoginEntry() {
        let service = FakeLoginService()
        let settings = LoginSettings(service: service, store: store)
        settings.setEnabled(true)
        XCTAssertTrue(settings.enabled)
        XCTAssertFalse(store.exists)
        settings.setEnabled(false)
        XCTAssertFalse(settings.enabled)
    }

    func testPermissionFailureDoesNotFallBack() {
        let service = FakeLoginService()
        service.failure = NSError(domain: NSPOSIXErrorDomain, code: 1)
        let settings = LoginSettings(service: service, store: store)
        settings.setEnabled(true)
        XCTAssertNotNil(settings.error)
        XCTAssertFalse(store.exists)
        XCTAssertFalse(settings.enabled)
    }

    func testPendingApprovalRemainsEnabledWithoutDuplicateAgent() {
        let service = FakeLoginService()
        service.state = .needsApproval
        let settings = LoginSettings(service: service, store: store)
        XCTAssertTrue(settings.enabled)
        XCTAssertTrue(settings.requiresApproval)
        XCTAssertFalse(store.exists)
    }

    func testExistingAgentIsUpdatedAfterMovingApp() throws {
        try store.enable()
        let moved = directory.appendingPathComponent("Przeniesiona.app")
        try FileManager.default.moveItem(at: app, to: moved)
        let movedStore = LoginAgentStore(file: store.file, app: moved)
        let settings = LoginSettings(service: FakeLoginService(), store: movedStore)
        XCTAssertTrue(settings.enabled)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: store.file), format: nil) as? [String: Any])
        XCTAssertEqual((plist["ProgramArguments"] as? [String])?.last, moved.path)
    }
}
