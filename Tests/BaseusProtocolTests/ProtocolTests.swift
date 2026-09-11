import XCTest
@testable import BaseusProtocol

final class ProtocolTests: XCTestCase {
    func decode(_ bytes: [UInt8], pending: ANCMode? = nil) -> DeviceEvent? {
        BP1Protocol.decode(Data(bytes), pendingANC: pending)
    }

    func testHardwareBatteryCaptures() {
        XCTAssertEqual(decode([0xAA, 0x02, 100, 0, 100, 1]), .battery(left: 100, right: 100))
        XCTAssertEqual(decode([0xAA, 0x02, 0, 0, 100, 1]), .battery(left: 0, right: 100))
        XCTAssertEqual(decode([0xAA, 0x27, 50, 0]), .batteryCase(percent: 50, charging: false))
        XCTAssertEqual(decode([0xAA, 0x27, 50, 1]), .batteryCase(percent: 50, charging: true))
    }

    func testFirmwareFlatAncAckResolvesAgainstPendingCommand() {
        for mode in ANCMode.allCases {
            XCTAssertEqual(decode([0xAA, 0x34, 1], pending: mode), .anc(mode, level: nil))
        }
        XCTAssertEqual(decode([0xAA, 0x34, 0], pending: .active), .anc(.off, level: nil))
        XCTAssertNil(decode([0xAA, 0x34, 1])) // No fabricated ANC state on unsolicited ACK.
        XCTAssertEqual(decode([0xAA, 0x33, 1, 0x68]), .anc(.active, level: 0x68))
        XCTAssertEqual(decode([0xAA, 0x32, 2, 0xFF]), .anc(.transparency, level: nil))
    }

    func testGestureNotificationsUsePayloadModeInsteadOfOpcode() {
        // Real BP1 notification captured after a gesture; no app command pending.
        XCTAssertEqual(decode([0xAA, 0x33, 0x02, 0xFF]), .anc(.transparency, level: nil))
        XCTAssertEqual(decode([0xAA, 0x33, 0x00, 0xFF]), .anc(.off, level: nil))
        XCTAssertEqual(decode([0xAA, 0x33, 0x01, 0x68]), .anc(.active, level: 0x68))
        XCTAssertNil(decode([0xAA, 0x33, 0xFF, 0xFF]))
        var state = DeviceState()
        state.apply(.anc(.active, level: 104))
        state.apply(decode([0xAA, 0x33, 0x00, 0xFF])!)
        XCTAssertEqual(state.anc, .off)
        state.apply(decode([0xAA, 0x33, 0x02, 0xFF])!)
        XCTAssertEqual(state.anc, .transparency)
        XCTAssertEqual(state.level, 104) // FF in an off/transparency event is not strength.
    }

    func testBatteryTimestampsOnlyAdvanceOnTheirOwnReports() {
        var state = DeviceState()
        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 200)
        state.apply(.battery(left: 100, right: 100), at: first)
        state.apply(.batteryCase(percent: 80, charging: false), at: first)
        state.apply(.anc(.active, level: 104), at: second)
        XCTAssertEqual(state.budsUpdatedAt, first)
        XCTAssertEqual(state.caseUpdatedAt, first)
        // Identical percentages still constitute a new device report.
        state.apply(.battery(left: 100, right: 100), at: second)
        XCTAssertEqual(state.budsUpdatedAt, second)
        XCTAssertEqual(state.caseUpdatedAt, first)
        state.apply(.battery(left: 100, right: 90), at: second)
        XCTAssertEqual(state.right, 90)
        state = DeviceState()
        XCTAssertNil(state.budsUpdatedAt)
        XCTAssertNil(state.caseUpdatedAt)
    }

    func testBatteryRefreshRequiresActualReportsNotCommandAcks() {
        var progress = BatteryRefreshProgress()
        progress.receive(.eq(.balanced))
        progress.receive(.anc(.active, level: nil))
        XCTAssertFalse(progress.budsReceived)
        XCTAssertFalse(progress.caseReceived)
        progress.receive(.battery(left: 100, right: 90))
        XCTAssertFalse(progress.complete)
        XCTAssertTrue(progress.summary.contains("Etui: ostatni niezależny raport"))
        progress.receive(.batteryCase(percent: 80, charging: false))
        XCTAssertTrue(progress.complete)
    }

    func testKeepaliveAndFlatGameAckDoNotOverwriteState() {
        XCTAssertNil(decode([0xAA, 0x30, 0]))
        XCTAssertNil(decode([0xAA, 0x24, 1]))
        XCTAssertEqual(decode([0xAA, 0x23, 0]), .game(false))
        XCTAssertEqual(decode([0xAA, 0x23, 1]), .game(true))
    }

    func testGoldenOutgoingCommands() {
        XCTAssertEqual(Command.handshake.bytes, Data([0xBA, 5, 0]))
        XCTAssertEqual(Command.queryEQ.bytes, Data([0xBA, 0x42]))
        XCTAssertEqual(Command.queryBattery.bytes, Data([0xBA, 0x02]))
        XCTAssertEqual(Command.anc(.off, 104).bytes, Data([0xBA, 0x34, 0, 0xFF]))
        XCTAssertEqual(Command.anc(.transparency, 104).bytes, Data([0xBA, 0x34, 2, 0xFF]))
        XCTAssertEqual(Command.anc(.active, 104).bytes, Data([0xBA, 0x34, 1, 0x68]))
        XCTAssertEqual(Command.anc(.active, 0).bytes, Data([0xBA, 0x34, 1, 0x10]))
        XCTAssertEqual(Command.game(false).bytes, Data([0xBA, 0x24, 0]))
        XCTAssertEqual(Command.game(true).bytes, Data([0xBA, 0x24, 1]))
        for side in Earbud.allCases {
            XCTAssertEqual(Command.find(side, true).bytes, Data([0xBA, 0x10, side.rawValue, 1]))
            XCTAssertEqual(Command.find(side, false).bytes, Data([0xBA, 0x10, side.rawValue, 0]))
        }
        for preset in EQPreset.allCases {
            XCTAssertEqual(Command.eq(preset).bytes, Data([0xBA, 0x43, preset.rawValue]))
            for op: UInt8 in [0x42, 0x43] { XCTAssertEqual(decode([0xAA, op, preset.rawValue]), .eq(preset)) }
        }
    }

    func testMalformedFramesNeverProduceFakeState() {
        let invalid: [[UInt8]] = [[], [0xAA], [0xAA, 0x42], [0, 0x42, 0],
            [0xAA, 0x02, 100, 0, 90], [0xAA, 0x02, 255, 0, 100, 1],
            [0xAA, 0x02, 100, 1, 100, 1], [0xAA, 0x27, 50], [0xAA, 0x27, 101, 0],
            [0xAA, 0x27, 50, 2], [0xAA, 0x43, 255], [0xAA, 0x23, 2], [0xAA, 0x99, 0]]
        for bytes in invalid { XCTAssertNil(decode(bytes), "\(bytes)") }
    }

    func testAllSingleBytePayloadsAreHandledWithoutCrashing() {
        for op in UInt8.min...UInt8.max {
            for payload in UInt8.min...UInt8.max { _ = decode([0xAA, op, payload]) }
        }
    }

    func testIndependentStateAndReset() {
        var state = DeviceState()
        XCTAssertNil(state.anc)
        XCTAssertNil(state.game)
        state.apply(.anc(.active, level: 104))
        state.apply(.game(true))
        state.apply(.battery(left: 0, right: 90))
        state.apply(.batteryCase(percent: 50, charging: false))
        XCTAssertEqual(state.anc, .active)
        XCTAssertEqual(state.level, 104)
        XCTAssertEqual(state.game, true)
        XCTAssertEqual(state.left, 0)
        XCTAssertFalse(state.caseCharging)
        state = DeviceState()
        XCTAssertNil(state.left)
        XCTAssertNil(state.level)
    }

    func testOnlyRelatedStateAcknowledgesCommand() {
        XCTAssertTrue(Command.game(false).accepts(.game(false)))
        XCTAssertFalse(Command.game(true).accepts(.anc(.active, level: nil)))
        XCTAssertFalse(Command.queryEQ.accepts(.battery(left: 50, right: 50)))
        XCTAssertTrue(Command.queryEQ.accepts(.eq(.bass)))
        XCTAssertFalse(Command.handshake.needsStateReply)
        XCTAssertFalse(Command.find(.left, false).needsStateReply)
        XCTAssertTrue(Command.anc(.off, 0).needsStateReply)
    }

    func testTransactionWaitsForWriteAndStateInEitherOrder() {
        var writeFirst = CommandTransaction(.game(false))
        writeFirst.acknowledgeWrite()
        XCTAssertFalse(writeFirst.isComplete)
        writeFirst.receive(.battery(left: 90, right: 90))
        XCTAssertFalse(writeFirst.isComplete)
        writeFirst.receive(.game(false))
        XCTAssertTrue(writeFirst.isComplete)

        var stateFirst = CommandTransaction(.anc(.off, 255))
        stateFirst.receive(.anc(.off, level: nil))
        XCTAssertFalse(stateFirst.isComplete)
        stateFirst.acknowledgeWrite()
        XCTAssertTrue(stateFirst.isComplete)
    }

    func testTransportOnlyCommandsAndFreshTransactions() {
        var handshake = CommandTransaction(.handshake)
        XCTAssertFalse(handshake.isComplete)
        handshake.acknowledgeWrite()
        XCTAssertTrue(handshake.isComplete)
        var next = CommandTransaction(.queryEQ)
        next.acknowledgeWrite()
        XCTAssertFalse(next.isComplete)
        next.receive(.eq(.balanced))
        XCTAssertTrue(next.isComplete)
    }

    func testModelMatchingDoesNotAcceptUnverifiedModels() {
        XCTAssertTrue(BP1Protocol.supports(name: "BASS BP1 PRO"))
        XCTAssertTrue(BP1Protocol.supports(name: "  Bass   BP1 Pro  "))
        XCTAssertTrue(BP1Protocol.supports(name: "Bass BP1 Pro ANC"))
        XCTAssertFalse(BP1Protocol.supports(name: "Baseus Bowie H1"))
        XCTAssertFalse(BP1Protocol.supports(name: "Bass BP1 Pro 2"))
    }
}
