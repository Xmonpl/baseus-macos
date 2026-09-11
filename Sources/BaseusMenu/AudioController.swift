import Foundation
import Combine
import BaseusProtocol

struct PairedHeadphones: Identifiable, Equatable {
    let id: String // Classic Bluetooth address, not the CoreBluetooth UUID.
    let name: String
}

struct AudioOutput: Equatable {
    let id: UInt32
    let uid: String
    let name: String
}

protocol AudioBackend: AnyObject {
    var changed: (() -> Void)? { get set }
    func pairedHeadphones() -> [PairedHeadphones]
    func connect(_ device: PairedHeadphones, completion: @escaping (String?) -> Void)
    func outputs() -> [AudioOutput]
    func defaultOutput() -> UInt32?
    func selectOutput(_ id: UInt32) -> Bool
}

/// BLE control and macOS audio are independent connections. Only CoreAudio can
/// confirm that the headphones are available for playback and selected as output.
final class AudioController: ObservableObject {
    @Published private(set) var status = "Audio niepołączone"
    @Published private(set) var working = false
    @Published private(set) var ready = false
    @Published private(set) var choices: [PairedHeadphones] = []
    @Published var automatic: Bool {
        didSet {
            defaults.set(automatic, forKey: "automaticAudio")
            if !automatic {
                cancelAttempt()
                if !ready { status = "Automatyczne audio wyłączone" }
            }
            else if sessionID != nil { connect() }
        }
    }
    private let backend: AudioBackend
    private let defaults: UserDefaults
    private var sessionID: UUID?
    private var selected: PairedHeadphones?
    private var attempt = UUID()
    private var timer: Timer?
    private var ticks = 0

    init(backend: AudioBackend = SystemAudioBackend(), defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
        automatic = defaults.object(forKey: "automaticAudio") as? Bool ?? true
        backend.changed = { [weak self] in self?.refresh() }
    }

    func beginSession(_ id: UUID) {
        endSession()
        sessionID = id
        if automatic { connect() } else { status = "Automatyczne audio wyłączone" }
    }

    func endSession() {
        cancelAttempt()
        sessionID = nil
        selected = nil
        choices = []
        ready = false
        status = "Audio niepołączone"
        // Losing BLE or quitting the tray app must not cut off music.
    }

    func forget(_ id: UUID) { defaults.removeObject(forKey: "audioDevice.\(id.uuidString)") }

    func connect(selectedID: String? = nil) {
        guard let sessionID else { return }
        cancelAttempt()
        ready = false
        let devices = backend.pairedHeadphones()
        let saved = selectedID ?? defaults.string(forKey: "audioDevice.\(sessionID.uuidString)")
        let match = devices.first { $0.id == saved } ?? (devices.count == 1 ? devices.first : nil)
        guard let match else {
            choices = devices
            status = devices.isEmpty ? "Sparuj słuchawki w ustawieniach Bluetooth" : "Wybierz słuchawki do odtwarzania"
            return
        }
        choices = []
        selected = match
        defaults.set(match.id, forKey: "audioDevice.\(sessionID.uuidString)")
        working = true
        status = "Łączenie audio…"
        let token = attempt
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        // Already available A2DP output requires no new baseband connection.
        if output(for: match) != nil { refresh(); return }
        backend.connect(match) { [weak self] error in
            guard let self, self.attempt == token, self.sessionID != nil, self.working else { return }
            if let error {
                self.cancelAttempt()
                self.status = "Nie udało się połączyć audio: \(error)"
            } else { self.refresh() }
        }
    }

    func poll() {
        guard working else { return }
        ticks += 1
        refresh()
        if working && ticks >= 25 {
            cancelAttempt()
            status = "macOS nie udostępnił wyjścia audio. Ponów lub otwórz ustawienia Bluetooth."
        }
    }

    func refresh() {
        guard sessionID != nil, let selected else { return }
        guard let output = output(for: selected) else {
            ready = false
            if !working { status = "Audio niepołączone" }
            return
        }
        if working && backend.defaultOutput() != output.id {
            guard backend.selectOutput(output.id) else {
                cancelAttempt()
                status = "Audio dostępne, ale macOS odmówił wyboru wyjścia"
                return
            }
        }
        ready = backend.defaultOutput() == output.id
        if ready {
            cancelAttempt()
            status = "Audio połączone · wyjście dźwięku"
        } else if !working {
            status = "Audio dostępne · wybrane inne wyjście"
        }
        // CoreAudio change notifications observe later user routing changes;
        // they never steal the output back after this bounded connection attempt.
    }

    private func output(for device: PairedHeadphones) -> AudioOutput? {
        let outputs = backend.outputs()
        let address = device.id.filter { $0.isHexDigit }.uppercased()
        let exact = outputs.filter { output in
            let uid = output.uid.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "").uppercased()
            return address.count == 12 && uid.contains(address)
        }
        if exact.count == 1 { return exact[0] }
        // A name is sufficient only when both sides are unambiguous.
        let named = outputs.filter { $0.name.caseInsensitiveCompare(device.name) == .orderedSame }
        let paired = backend.pairedHeadphones().filter { $0.name.caseInsensitiveCompare(device.name) == .orderedSame }
        return named.count == 1 && paired.count == 1 ? named[0] : nil
    }

    private func cancelAttempt() {
        attempt = UUID()
        timer?.invalidate(); timer = nil
        ticks = 0
        working = false
    }

    deinit { timer?.invalidate() }
}
