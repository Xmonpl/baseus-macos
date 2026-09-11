import Foundation
import CoreAudio
import IOBluetooth
import BaseusProtocol

final class SystemAudioBackend: AudioBackend {
    var changed: (() -> Void)?
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var requests: [UUID: ClassicConnection] = [:]

    init() {
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = Self.address(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.changed?() }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
                listeners.append((address, block))
            }
        }
    }

    func pairedHeadphones() -> [PairedHeadphones] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).compactMap {
            guard let name = $0.name, BP1Protocol.supports(name: name), let address = $0.addressString else { return nil }
            return PairedHeadphones(id: address, name: name)
        }
    }

    func connect(_ device: PairedHeadphones, completion: @escaping (String?) -> Void) {
        guard let classic = IOBluetoothDevice(addressString: device.id) else { completion("Nie znaleziono urządzenia"); return }
        if classic.isConnected() { completion(nil); return }
        let token = UUID()
        let request = ClassicConnection(device: classic) { [weak self] error in
            self?.requests.removeValue(forKey: token)
            completion(error)
        }
        requests[token] = request
        request.start()
    }

    func outputs() -> [AudioOutput] {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.compactMap { device in
            guard uint(device, kAudioDevicePropertyTransportType) == kAudioDeviceTransportTypeBluetooth else { return nil }
            var streams = Self.address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr, streamSize > 0,
                  uint(device, kAudioDevicePropertyDeviceIsAlive) == 1,
                  let uid = string(device, kAudioDevicePropertyDeviceUID), let name = string(device, kAudioObjectPropertyName) else { return nil }
            return AudioOutput(id: device, uid: uid, name: name)
        }
    }

    func defaultOutput() -> UInt32? { uint(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) }

    func selectOutput(_ id: UInt32) -> Bool {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var value = id
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout.size(ofValue: value)), &value) == noErr
    }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func uint(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = Self.address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: value))
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = Self.address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: value))
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    deinit {
        for (var address, block) in listeners {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
    }
}

private final class ClassicConnection: NSObject {
    private let device: IOBluetoothDevice
    private var completion: ((String?) -> Void)?
    private var timer: Timer?

    init(device: IOBluetoothDevice, completion: @escaping (String?) -> Void) {
        self.device = device
        self.completion = completion
    }

    func start() {
        // A non-nil delegate makes this asynchronous; never block the menu's UI.
        let result = device.openConnection(self, withPageTimeout: 0x2000, authenticationRequired: false)
        if result != kIOReturnSuccess { finish("Bluetooth: \(result)"); return }
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in self?.finish("Przekroczono czas oczekiwania") }
    }

    @objc func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        finish(status == kIOReturnSuccess || device.isConnected() ? nil : "Bluetooth: \(status)")
    }

    private func finish(_ error: String?) {
        timer?.invalidate()
        let callback = completion
        completion = nil
        callback?(error)
    }
}
