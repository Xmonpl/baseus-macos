import XCTest
@testable import BaseusMenu

private final class FakeAudio: AudioBackend {
    var changed: (() -> Void)?
    var paired = [PairedHeadphones(id: "AA-BB-CC-DD-EE-FF", name: "Bass BP1 Pro")]
    var available: [AudioOutput] = []
    var active: UInt32? = 1
    var connectCalls = 0
    var selectionCalls: [UInt32] = []
    var pending: ((String?) -> Void)?
    var permitSelection = true
    func pairedHeadphones() -> [PairedHeadphones] { paired }
    func connect(_ device: PairedHeadphones, completion: @escaping (String?) -> Void) { connectCalls += 1; pending = completion }
    func outputs() -> [AudioOutput] { available }
    func defaultOutput() -> UInt32? { active }
    func selectOutput(_ id: UInt32) -> Bool {
        selectionCalls.append(id)
        if permitSelection { active = id }
        return permitSelection
    }
}

final class AudioControllerTests: XCTestCase {
    private let output = AudioOutput(id: 42, uid: "AA:BB:CC:DD:EE:FF:output", name: "Bass BP1 Pro")
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        suite = "BaseusMenuTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testClassicConnectionIsNotTreatedAsAudioReady() {
        let backend = FakeAudio()
        let audio = AudioController(backend: backend, defaults: defaults)
        audio.beginSession(UUID())
        XCTAssertEqual(backend.connectCalls, 1)
        backend.pending?(nil)
        XCTAssertFalse(audio.ready)
        XCTAssertTrue(audio.working)
        backend.available = [output]
        audio.poll()
        XCTAssertTrue(audio.ready)
        XCTAssertFalse(audio.working)
        XCTAssertEqual(backend.selectionCalls, [42])
    }

    func testAvailableAudioIsSelectedWithoutReconnectingAndLaterUserChoiceIsRespected() {
        let backend = FakeAudio()
        backend.available = [output]
        let audio = AudioController(backend: backend, defaults: defaults)
        audio.beginSession(UUID())
        XCTAssertTrue(audio.ready)
        XCTAssertEqual(backend.connectCalls, 0)
        backend.active = 99
        backend.changed?()
        XCTAssertFalse(audio.ready)
        XCTAssertEqual(backend.selectionCalls, [42])
        audio.connect()
        XCTAssertTrue(audio.ready)
        XCTAssertEqual(backend.selectionCalls, [42, 42])
    }

    func testNoPairingAndAmbiguousDevicesNeverConnectBlindly() {
        let backend = FakeAudio()
        backend.paired = []
        let audio = AudioController(backend: backend, defaults: defaults)
        audio.beginSession(UUID())
        XCTAssertFalse(audio.working)
        XCTAssertEqual(backend.connectCalls, 0)
        backend.paired = [PairedHeadphones(id: "AA", name: "Bass BP1 Pro"), PairedHeadphones(id: "BB", name: "Bass BP1 Pro")]
        audio.connect()
        XCTAssertEqual(audio.choices.count, 2)
        XCTAssertEqual(backend.connectCalls, 0)
        audio.connect(selectedID: "BB")
        XCTAssertEqual(backend.connectCalls, 1)
    }

    func testLateCallbacksAfterDisconnectCannotSelectOutput() {
        let backend = FakeAudio()
        let audio = AudioController(backend: backend, defaults: defaults)
        audio.beginSession(UUID())
        audio.endSession()
        backend.available = [output]
        backend.pending?(nil)
        backend.changed?()
        XCTAssertFalse(audio.ready)
        XCTAssertTrue(backend.selectionCalls.isEmpty)
    }

    func testTimeoutStopsAutomaticRouting() {
        let backend = FakeAudio()
        let audio = AudioController(backend: backend, defaults: defaults)
        audio.beginSession(UUID())
        for _ in 0..<25 { audio.poll() }
        XCTAssertFalse(audio.working)
        XCTAssertFalse(audio.ready)
        backend.available = [output]
        backend.pending?(nil)
        backend.changed?()
        XCTAssertTrue(backend.selectionCalls.isEmpty)
    }

    func testOptOutAndSelectionFailure() {
        let backend = FakeAudio()
        defaults.set(false, forKey: "automaticAudio")
        let audio = AudioController(backend: backend, defaults: defaults)
        audio.beginSession(UUID())
        XCTAssertEqual(backend.connectCalls, 0)
        backend.available = [output]
        backend.permitSelection = false
        audio.connect()
        XCTAssertFalse(audio.working)
        XCTAssertFalse(audio.ready)
        XCTAssertEqual(backend.selectionCalls, [42])
    }

    func testDuplicateNamesRequireAddressMatch() {
        let backend = FakeAudio()
        backend.available = [output, AudioOutput(id: 43, uid: "11:22:33:44:55:66:output", name: "Bass BP1 Pro")]
        backend.paired.append(PairedHeadphones(id: "11-22-33-44-55-66", name: "Bass BP1 Pro"))
        let audio = AudioController(backend: backend, defaults: defaults)
        audio.beginSession(UUID())
        audio.connect(selectedID: "AA-BB-CC-DD-EE-FF")
        XCTAssertEqual(backend.selectionCalls, [42])
        XCTAssertTrue(audio.ready)
    }
}
