import AppKit
import CoreBluetooth
import Combine
import UserNotifications
import BaseusProtocol

struct DiscoveredDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
    let supported: Bool
}

/// CoreBluetooth and UI state share the main queue. No background polling thread.
final class BluetoothController: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    let audio = AudioController()
    @Published private(set) var status = "Uruchamianie Bluetooth…"
    @Published private(set) var connected = false
    @Published private(set) var scanning = false
    @Published private(set) var connecting = false
    @Published private(set) var busy = false
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var state = DeviceState()
    @Published private(set) var deviceName = "Bass BP1 Pro ANC"
    @Published private(set) var connectedAt: Date?
    @Published private(set) var finding: Earbud?
    @Published private(set) var refreshingBattery = false
    @Published private(set) var batteryRefreshMessage: String?
    @Published var error: String?
    @Published var autoReconnect: Bool {
        didSet {
            UserDefaults.standard.set(autoReconnect, forKey: "autoReconnect")
            if !autoReconnect { retryTimer?.invalidate() }
            else if !connected && !connecting && !manuallyStopped { scan() }
        }
    }
    @Published var batteryAlerts: Bool {
        didSet {
            UserDefaults.standard.set(batteryAlerts, forKey: "batteryAlerts")
            if batteryAlerts {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { allowed, failure in
                    DispatchQueue.main.async {
                        if !allowed { self.error = failure?.localizedDescription ?? "Włącz powiadomienia dla Baseus Menu w Ustawieniach systemowych." }
                    }
                }
            }
        }
    }
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var scanTimer: Timer?
    private var retryTimer: Timer?
    private var connectionTimer: Timer?
    private var commandTimer: Timer?
    private var findTimer: Timer?
    private var batteryRefreshTimer: Timer?
    private var batteryPollTimer: Timer?
    private var batteryRefreshIsManual = false
    private var batteryRefreshProgress = BatteryRefreshProgress()
    private var diagnosticRefreshOnConnect = CommandLine.arguments.contains("--refresh-battery-once")
    private var retryDelay: TimeInterval = 5
    private var manuallyStopped = false
    private var sleeping = false
    private var queue: [Command] = []
    private var transaction: CommandTransaction?
    private var current: Command? { transaction?.command }
    private var lowBatteryComponents: Set<String> = []
    private var log: [String] = []
    private var journal: DiagnosticJournal?
    private var exportPanel: NSSavePanel?
    private var observers: [NSObjectProtocol] = []
    private var preferredID: UUID? {
        UserDefaults.standard.string(forKey: "preferredDevice").flatMap(UUID.init(uuidString:))
    }
    var preferredName: String? { UserDefaults.standard.string(forKey: "preferredName") }

    override init() {
        autoReconnect = UserDefaults.standard.object(forKey: "autoReconnect") as? Bool ?? true
        batteryAlerts = UserDefaults.standard.bool(forKey: "batteryAlerts")
        super.init()
        journal = DiagnosticJournal()
        record("Baseus Menu \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") · start")
        central = CBCentralManager(delegate: self, queue: .main)
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.sleeping = true
            self.stopConnection(manual: false)
            self.status = "Mac jest uśpiony"
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.sleeping = false
            if self.autoReconnect && !self.manuallyStopped { self.scan() }
        })
    }

    #if DEBUG
    /// Offline fixture for rendering the real SwiftUI panel without using the radio.
    init(previewConnected: Bool) {
        autoReconnect = false
        batteryAlerts = false
        super.init()
        connected = previewConnected
        status = previewConnected ? "Połączono · podgląd" : "Nie znaleziono słuchawek"
        if previewConnected {
            state.apply(.battery(left: 85, right: 90))
            state.apply(.batteryCase(percent: 50, charging: true))
            state.apply(.anc(.active, level: 104))
            state.apply(.eq(.balanced))
            state.apply(.game(false))
            connectedAt = Date()
        }
    }
    #endif

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            stopConnection(manual: false)
            switch central.state {
            case .poweredOff: status = "Bluetooth jest wyłączony"
            case .unauthorized: status = "Brak dostępu do Bluetooth"
            case .unsupported: status = "Bluetooth LE jest niedostępny"
            case .resetting: status = "Bluetooth uruchamia się ponownie…"
            default: status = "Oczekiwanie na Bluetooth…"
            }
            return
        }
        if !manuallyStopped && !sleeping { scan() }
    }

    func scan(userInitiated: Bool = false) {
        if userInitiated { manuallyStopped = false; error = nil; retryDelay = 5 }
        guard central.state == .poweredOn, !connected, !connecting, !sleeping else { return }
        retryTimer?.invalidate()
        scanTimer?.invalidate()
        central.stopScan()
        devices.removeAll()
        peripherals.removeAll()
        scanning = true
        status = "Szukam słuchawek w pobliżu…"
        if !userInitiated, autoReconnect, !manuallyStopped, let id = preferredID,
           let saved = central.retrievePeripherals(withIdentifiers: [id]).first {
            connect(saved)
            return
        }
        // Some firmware omits service UUIDs from advertisements, so filter names locally.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        for item in central.retrieveConnectedPeripherals(withServices: [CBUUID(string: BP1Protocol.service)]) {
            discovered(item, name: item.name ?? "Baseus", rssi: 0)
        }
        guard scanning else { return }
        scanTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.central.stopScan()
            self.scanning = false
            self.status = self.devices.isEmpty ? "Nie znaleziono słuchawek" : "Wybierz słuchawki"
            self.scheduleRetry()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        discovered(peripheral, name: advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "", rssi: RSSI.intValue)
    }

    private func discovered(_ item: CBPeripheral, name: String, rssi: Int) {
        let supported = BP1Protocol.supports(name: name)
        guard supported || name.localizedCaseInsensitiveContains("baseus") || name.localizedCaseInsensitiveContains("bass bp") else { return }
        peripherals[item.identifier] = item
        devices.removeAll { $0.id == item.identifier }
        devices.append(DiscoveredDevice(id: item.identifier, name: name, rssi: rssi, supported: supported))
        devices.sort { $0.name < $1.name }
        if supported, item.identifier == preferredID, autoReconnect, !manuallyStopped, !connecting, !connected { connect(item) }
    }

    func connect(id: UUID) {
        guard let device = devices.first(where: { $0.id == id }), device.supported,
              let item = peripherals[id], !connecting, !connected else { return }
        manuallyStopped = false
        error = nil
        connect(item)
    }

    private func connect(_ item: CBPeripheral) {
        central.stopScan()
        scanTimer?.invalidate()
        retryTimer?.invalidate()
        scanning = false
        connecting = true
        status = "Łączenie z \(item.name ?? "Baseus")…"
        peripheral = item
        item.delegate = self
        central.connect(item)
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 18, repeats: false) { [weak self, weak item] _ in
            guard let self, let item, self.peripheral === item, !self.connected else { return }
            self.fail("Słuchawki nie odpowiadają. Otwórz etui, wyjmij słuchawki i zamknij aplikację Baseus na telefonie.")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.peripheral === peripheral else { return }
        status = "Odczyt usług Bluetooth…"
        peripheral.discoverServices([CBUUID(string: BP1Protocol.service)])
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard self.peripheral === peripheral else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: BP1Protocol.service) }) else {
            fail(error?.localizedDescription ?? "Urządzenie nie udostępnia usługi sterowania BP1 Pro."); return
        }
        peripheral.discoverCharacteristics([CBUUID(string: BP1Protocol.write), CBUUID(string: BP1Protocol.notify)], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard self.peripheral === peripheral else { return }
        guard error == nil else { fail(error!.localizedDescription); return }
        writeCharacteristic = service.characteristics?.first { $0.uuid == CBUUID(string: BP1Protocol.write) }
        notifyCharacteristic = service.characteristics?.first { $0.uuid == CBUUID(string: BP1Protocol.notify) }
        guard let writeCharacteristic, writeCharacteristic.properties.contains(.write),
              let notifyCharacteristic, notifyCharacteristic.properties.contains(.notify) else {
            fail("Nie znaleziono zgodnych charakterystyk zapisu i powiadomień."); return
        }
        status = "Włączanie powiadomień słuchawek…"
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral, characteristic.uuid == CBUUID(string: BP1Protocol.notify) else { return }
        guard error == nil, characteristic.isNotifying else { fail(error?.localizedDescription ?? "Subskrypcja Bluetooth została przerwana."); return }
        connectionTimer?.invalidate()
        connected = true
        connecting = false
        connectedAt = Date()
        deviceName = peripheral.name ?? "Bass BP1 Pro ANC"
        status = "Sterowanie BLE połączone"
        self.error = nil
        retryDelay = 5
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "preferredDevice")
        UserDefaults.standard.set(deviceName, forKey: "preferredName")
        record("Połączono; subskrypcja GATT aktywna")
        send(.handshake)
        send(.queryEQ)
        audio.beginSession(peripheral.identifier)
        batteryPollTimer?.invalidate()
        batteryPollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refreshBattery(automatic: true) }
        batteryPollTimer?.tolerance = 10
        if diagnosticRefreshOnConnect {
            diagnosticRefreshOnConnect = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.refreshBattery() }
        }
    }

    func send(_ command: Command) {
        guard connected, peripheral != nil, writeCharacteristic != nil else { return }
        guard queue.count < 16 else { error = "Poczekaj na wykonanie poprzednich poleceń."; return }
        queue.append(command)
        pump()
    }

    private func pump() {
        guard current == nil, !queue.isEmpty, let peripheral, let writeCharacteristic, connected else { return }
        let command = queue.removeFirst()
        transaction = CommandTransaction(command)
        busy = true
        record("TX " + command.bytes.hex)
        peripheral.writeValue(command.bytes, for: writeCharacteristic, type: .withResponse)
        commandTimer?.invalidate()
        commandTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self else { return }
            // Tear down on timeout so a late flat ACK cannot confirm a newer command.
            self.fail("Brak potwierdzenia polecenia. Połączenie zostanie nawiązane ponownie.")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral, characteristic.uuid == writeCharacteristic?.uuid, current != nil else { return }
        guard error == nil else { fail("Błąd zapisu: \(error!.localizedDescription)"); return }
        transaction?.acknowledgeWrite()
        completeIfReady()
    }

    private func completeIfReady() {
        guard transaction?.isComplete == true else { return }
        commandTimer?.invalidate()
        transaction = nil
        busy = false
        pump()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral, characteristic.uuid == notifyCharacteristic?.uuid else { return }
        guard error == nil, let data = characteristic.value else { fail(error?.localizedDescription ?? "Błąd odczytu Bluetooth."); return }
        record("RX " + data.hex)
        var pendingMode: ANCMode?
        if case let .anc(mode, _) = current { pendingMode = mode }
        guard let event = BP1Protocol.decode(data, pendingANC: pendingMode) else { return }
        state.apply(event)
        if refreshingBattery {
            batteryRefreshProgress.receive(event)
            // BA02 requests the buds. Case reports arrive independently.
            if batteryRefreshProgress.budsReceived { finishBatteryRefresh() }
        }
        if case .anc = event, case let .anc(mode, level) = current, mode == .active, state.anc == .active { state.level = level }
        checkBattery(event)
        transaction?.receive(event)
        completeIfReady()
    }

    func find(_ side: Earbud) {
        guard connected, !busy, finding == nil else { return }
        finding = side
        send(.find(side, true))
        findTimer?.invalidate()
        findTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in self?.stopFinding() }
    }

    func refreshBattery(automatic: Bool = false) {
        guard connected, !busy, finding == nil, !refreshingBattery else { return }
        refreshingBattery = true
        batteryRefreshIsManual = !automatic
        batteryRefreshProgress = BatteryRefreshProgress()
        if !automatic { batteryRefreshMessage = "Oczekiwanie na nowy raport…" }
        record("Zapytanie o baterię BA 02")
        // Read command found in the official Android app's bytecode. State and
        // timestamps still change only on actual incoming battery reports.
        send(.queryBattery)
        batteryRefreshTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in self?.finishBatteryRefresh() }
    }

    private func finishBatteryRefresh() {
        guard refreshingBattery else { return }
        batteryRefreshTimer?.invalidate()
        refreshingBattery = false
        if batteryRefreshIsManual { batteryRefreshMessage = batteryRefreshProgress.summary }
        record(batteryRefreshProgress.summary)
    }

    func stopFinding() {
        findTimer?.invalidate()
        if let finding { send(.find(finding, false)) }
        finding = nil
    }

    func disconnect() { stopConnection(manual: true); status = "Rozłączono ręcznie" }

    func forget() {
        if let id = preferredID { audio.forget(id) }
        disconnect()
        UserDefaults.standard.removeObject(forKey: "preferredDevice")
        UserDefaults.standard.removeObject(forKey: "preferredName")
        devices.removeAll()
        status = "Zapomniano urządzenie"
    }

    private func stopConnection(manual: Bool) {
        if manual { manuallyStopped = true }
        central.stopScan()
        [scanTimer, retryTimer, connectionTimer, commandTimer, findTimer].forEach { $0?.invalidate() }
        if let peripheral {
            // Best effort stop before disconnect. Firmware may keep ringing if radio is lost.
            if let finding, let writeCharacteristic, peripheral.state == .connected {
                peripheral.writeValue(Command.find(finding, false).bytes, for: writeCharacteristic, type: .withResponse)
            }
            central.cancelPeripheralConnection(peripheral)
        }
        resetSession()
    }

    private func resetSession() {
        batteryRefreshTimer?.invalidate()
        batteryPollTimer?.invalidate()
        refreshingBattery = false
        batteryRefreshMessage = nil
        audio.endSession()
        peripheral?.delegate = nil
        peripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        connected = false; connecting = false; scanning = false; busy = false
        state = DeviceState()
        connectedAt = nil
        finding = nil
        queue.removeAll(); transaction = nil
        [connectionTimer, commandTimer, findTimer].forEach { $0?.invalidate() }
    }

    private func fail(_ message: String) {
        error = message
        record("BŁĄD " + message)
        stopConnection(manual: false)
        status = "Połączenie przerwane"
        scheduleRetry()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral === peripheral else { return }
        fail(error?.localizedDescription ?? "Nie udało się połączyć.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral === peripheral else { return }
        if finding != nil { self.error = "Utracono połączenie podczas szukania. Jeśli sygnał nadal trwa, włóż słuchawki do etui." }
        record("Rozłączono: " + (error?.localizedDescription ?? "urządzenie zakończyło połączenie"))
        resetSession()
        status = "Słuchawki rozłączone"
        scheduleRetry()
    }

    private func scheduleRetry() {
        guard autoReconnect, preferredID != nil, !manuallyStopped, !sleeping, central.state == .poweredOn else { return }
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: retryDelay, repeats: false) { [weak self] _ in self?.scan() }
        retryDelay = min(retryDelay * 2, 60)
    }

    private func checkBattery(_ event: DeviceEvent) {
        switch event {
        case let .battery(left, right):
            alertBattery("Lewa słuchawka", percent: left, ignoreZero: true)
            alertBattery("Prawa słuchawka", percent: right, ignoreZero: true)
        case let .batteryCase(percent, charging):
            if charging { lowBatteryComponents.remove("Etui") }
            else { alertBattery("Etui", percent: percent, ignoreZero: false) }
        default: break
        }
    }

    private func alertBattery(_ component: String, percent: Int, ignoreZero: Bool) {
        if percent >= 25 { lowBatteryComponents.remove(component); return }
        guard batteryAlerts, percent < 20, !(ignoreZero && percent == 0), !lowBatteryComponents.contains(component) else { return }
        lowBatteryComponents.insert(component)
        let content = UNMutableNotificationContent()
        content.title = "Baseus · \(component)"
        content.body = "Niski poziom baterii: \(percent)%"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "battery-\(component)", content: content, trigger: nil))
    }

    private func record(_ message: String) {
        let line = "\(Date().ISO8601Format()) \(message)"
        log.append(line)
        if log.count > 200 { log.removeFirst(log.count - 200) }
        do { try journal?.append(line) }
        catch { self.error = "Nie można zapisać dziennika diagnostycznego: \(error.localizedDescription)" }
    }

    func exportDiagnostics() {
        if let exportPanel { exportPanel.makeKeyAndOrderFront(nil); return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        exportPanel = panel
        panel.nameFieldStringValue = "Baseus-diagnostyka.txt"
        panel.level = .modalPanel
        panel.begin { [weak self] response in
            guard let self else { return }
            defer { self.exportPanel = nil }
            guard response == .OK, let url = panel.url else { return }
            let report = "Baseus Menu \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")\nmacOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n\(self.status)\nAudio: \(self.audio.status)\n\n" + self.log.joined(separator: "\n")
            do { try report.write(to: url, atomically: true, encoding: .utf8) }
            catch { self.error = "Nie udało się zapisać diagnostyki: \(error.localizedDescription)" }
        }
    }
}

private extension Data {
    var hex: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}
