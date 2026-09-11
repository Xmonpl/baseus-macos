/// A GATT write response acknowledges transport, not the requested device state.
/// Firmware is allowed to deliver its notification before the write callback.
public struct CommandTransaction {
    public let command: Command
    private var writeAcknowledged = false
    private var stateAcknowledged = false

    public init(_ command: Command) { self.command = command }
    public mutating func acknowledgeWrite() { writeAcknowledged = true }
    public mutating func receive(_ event: DeviceEvent) {
        if command.accepts(event) { stateAcknowledged = true }
    }
    public var isComplete: Bool {
        writeAcknowledged && (!command.needsStateReply || stateAcknowledged)
    }
}
