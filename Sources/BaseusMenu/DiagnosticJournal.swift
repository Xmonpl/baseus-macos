import Foundation

final class DiagnosticJournal {
    let url: URL
    private let limit: Int
    private(set) var lines: [String] = []
    init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/BaseusMenu/session.log"), limit: Int = 200) {
        self.url = url
        self.limit = max(1, limit)
    }
    func append(_ line: String) throws {
        lines.append(line)
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
