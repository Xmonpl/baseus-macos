import Foundation

// Port of elaxptr/baseus-desktop BP1 Pro ANC protocol. See THIRD_PARTY_NOTICES.md.
public enum ANCMode: UInt8, CaseIterable, Identifiable {
    case off = 0, active = 1, transparency = 2
    public var id: UInt8 { rawValue }
    public var title: String {
        switch self { case .off: return "Wyłączone"; case .active: return "ANC"; case .transparency: return "Kontakt" }
    }
}

public enum EQPreset: UInt8, CaseIterable, Identifiable {
    case balanced = 0, bass = 1, voice = 2, clear = 3
    public var id: UInt8 { rawValue }
    public var title: String {
        switch self {
        case .balanced: return "Zrównoważony"
        case .bass: return "Więcej basu"
        case .voice: return "Głos"
        case .clear: return "Wyrazisty · eksperymentalny"
        }
    }
}

public enum Earbud: UInt8, CaseIterable { case left = 0, right = 1 }

public enum Command: Equatable {
    case handshake, queryEQ, queryBattery
    case anc(ANCMode, UInt8), eq(EQPreset), game(Bool), find(Earbud, Bool)
    public var bytes: Data {
        switch self {
        case .handshake: return Data([0xBA, 0x05, 0x00])
        case .queryEQ: return Data([0xBA, 0x42])
        // Android FindEarPhoneActivity sends BA02 when opening the battery view.
        // Source: upstream docs/protocol/captures/bytecode-dump.txt, line 2026.
        case .queryBattery: return Data([0xBA, 0x02])
        case let .anc(mode, level): return Data([0xBA, 0x34, mode.rawValue, mode == .active ? max(0x10, level) : 0xFF])
        case let .eq(preset): return Data([0xBA, 0x43, preset.rawValue])
        case let .game(on): return Data([0xBA, 0x24, on ? 1 : 0])
        case let .find(side, on): return Data([0xBA, 0x10, side.rawValue, on ? 1 : 0])
        }
    }
    public var needsStateReply: Bool {
        switch self { case .anc, .eq, .game, .queryEQ: return true; default: return false }
    }
    public func accepts(_ event: DeviceEvent) -> Bool {
        switch (self, event) {
        case (.anc, .anc), (.eq, .eq), (.queryEQ, .eq), (.game, .game): return true
        default: return false
        }
    }
}

public enum DeviceEvent: Equatable {
    case battery(left: Int, right: Int)
    case batteryCase(percent: Int, charging: Bool)
    case anc(ANCMode, level: UInt8?)
    case eq(EQPreset)
    case game(Bool)
}

public enum BP1Protocol {
    public static let service = "53527AA4-29F7-AE11-4E74-997334782568"
    public static let write = "EE684B1A-1E9B-ED3E-EE55-F894667E92AC"
    public static let notify = "654B749C-E37F-AE1F-EBAB-40CA133E3690"

    public static func supports(name: String) -> Bool {
        let normalized = name.uppercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return ["BASS BP1 PRO", "BASEUS BASS BP1 PRO", "BASS BP1 PRO ANC"].contains(normalized)
    }

    /// One GATT notification is one frame; there is no stream framing or CRC.
    /// Malformed and unknown frames must never overwrite known state.
    public static func decode(_ data: Data, pendingANC: ANCMode? = nil) -> DeviceEvent? {
        let b = Array(data)
        guard b.count >= 3, b[0] == 0xAA else { return nil }
        switch b[1] {
        case 0x02:
            guard b.count >= 6, b[2] <= 100, b[4] <= 100, b[3] == 0, b[5] == 1 else { return nil }
            return .battery(left: Int(b[2]), right: Int(b[4]))
        case 0x27:
            guard b.count >= 4, b[2] <= 100, b[3] <= 1 else { return nil }
            return .batteryCase(percent: Int(b[2]), charging: b[3] == 1)
        case 0x32:
            guard b[2] == ANCMode.transparency.rawValue else { return nil }
            return .anc(.transparency, level: nil)
        case 0x33:
            // BP1 gestures use AA 33 [mode] [level], including 02=transparency
            // (captured 2026-09-10). The opcode is an event, not the ANC mode.
            guard let mode = ANCMode(rawValue: b[2]) else { return nil }
            return .anc(mode, level: mode == .active && b.count >= 4 && b[3] >= 0x10 ? b[3] : nil)
        case 0x34:
            // Some firmware always replies AA 34 01, even when switching OFF.
            if b[2] == 0 { return .anc(.off, level: nil) }
            guard let pendingANC else { return nil }
            return .anc(pendingANC, level: nil)
        case 0x42, 0x43:
            guard let preset = EQPreset(rawValue: b[2]) else { return nil }
            return .eq(preset)
        case 0x23:
            guard b[2] <= 1 else { return nil }
            return .game(b[2] == 1)
        // AA 30 is a keepalive; AA 24 is a flat ACK, not game state.
        default: return nil
        }
    }
}

public struct DeviceState: Equatable {
    public var left: Int?
    public var right: Int?
    public var caseBattery: Int?
    public var caseCharging = false
    public var budsUpdatedAt: Date?
    public var caseUpdatedAt: Date?
    public var anc: ANCMode?
    public var level: UInt8?
    public var eq: EQPreset?
    public var game: Bool?
    public init() {}
    public mutating func apply(_ event: DeviceEvent, at date: Date = Date()) {
        switch event {
        case let .battery(left, right):
            self.left = left; self.right = right; budsUpdatedAt = date
        case let .batteryCase(percent, charging):
            caseBattery = percent; caseCharging = charging; caseUpdatedAt = date
        case let .anc(mode, level): anc = mode; if let level { self.level = level }
        case let .eq(preset): eq = preset
        case let .game(on): game = on
        }
    }
}

public struct BatteryRefreshProgress {
    public private(set) var budsReceived = false
    public private(set) var caseReceived = false
    public init() {}
    public var complete: Bool { budsReceived && caseReceived }
    public mutating func receive(_ event: DeviceEvent) {
        switch event {
        case .battery: budsReceived = true
        case .batteryCase: caseReceived = true
        default: break
        }
    }
    public var summary: String {
        if complete { return "Odebrano nowy raport słuchawek i etui." }
        if budsReceived { return "Odświeżono słuchawki. Etui: ostatni niezależny raport urządzenia." }
        if caseReceived { return "Odebrano raport etui. Słuchawki nie przesłały nowego odczytu." }
        return "Brak nowego raportu. Wyświetlane wartości pochodzą z ostatniego odczytu; możesz ponownie połączyć sterowanie."
    }
}
