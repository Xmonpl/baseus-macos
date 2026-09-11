import XCTest
@testable import BaseusMenu

final class DiagnosticJournalTests: XCTestCase {
    func testJournalIsBoundedPrivateAndReplacedForNewSession() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("logs/session.log")
        let journal = DiagnosticJournal(url: url, limit: 2)
        try journal.append("first")
        try journal.append("second")
        try journal.append("third")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "second\nthird\n")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
        try DiagnosticJournal(url: url).append("new session")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "new session\n")
    }
}
