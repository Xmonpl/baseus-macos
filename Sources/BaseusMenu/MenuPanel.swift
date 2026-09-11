import SwiftUI
import AppKit
import ServiceManagement
import BaseusProtocol

private let accent = Color(red: 0.96, green: 0.76, blue: 0.13)

struct MenuPanel: View {
    @ObservedObject var controller: BluetoothController
    @StateObject private var login = LoginSettings()
    @State private var settingsVisible = false
    @State private var ancLevel = 104.0
    @State private var requestedFind: Earbud?
    @State private var confirmFind = false
    @AppStorage("experimentalEQ") private var experimentalEQ = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    deviceCard
                    if let error = controller.error { notice(error, dismiss: { controller.error = nil }) }
                    if controller.connected {
                        AudioPanel(audio: controller.audio)
                        batteries
                        ancCard
                        soundCard
                        findCard
                    } else { connectionCard }
                    if settingsVisible { settingsCard }
                }
                .padding(18)
            }
            footer
        }
        .frame(width: 380, height: 650)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
        .onChange(of: controller.state.level) { value in if let value { ancLevel = Double(value) } }
        .onChange(of: controller.connected) { value in if !value { ancLevel = 104 } }
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
        .alert("Wyjmij słuchawki z uszu", isPresented: $confirmFind) {
            Button("Anuluj", role: .cancel) { requestedFind = nil }
            Button("Odtwórz sygnał") { if let requestedFind { controller.find(requestedFind) }; requestedFind = nil }
        } message: {
            Text("Słuchawka wyda głośny sygnał. Aplikacja wyśle polecenie zatrzymania po 5 sekundach. Jeśli połączenie zostanie utracone, włóż słuchawkę do etui, aby przerwać sygnał.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform").font(.system(size: 18, weight: .bold)).foregroundStyle(accent)
            Text("baseus").font(.system(size: 23, weight: .bold, design: .rounded))
            Text("MENU").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(.secondary).padding(.top, 5)
            Spacer()
            Button { withAnimation(.easeInOut(duration: 0.18)) { settingsVisible.toggle() } } label: {
                Image(systemName: settingsVisible ? "slider.horizontal.3" : "gearshape").frame(width: 28, height: 28)
            }.buttonStyle(.plain).help("Ustawienia").accessibilityLabel("Ustawienia")
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .background(.bar)
    }

    private var deviceCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "earbuds")
                .font(.system(size: 34, weight: .medium))
                .frame(width: 62, height: 70)
                .foregroundStyle(scheme == .dark ? accent : .black)
                .background(accent.opacity(scheme == .dark ? 0.12 : 0.7), in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 7) {
                Text(controller.connected ? controller.deviceName : "Bass BP1 Pro ANC")
                    .font(.system(size: 16, weight: .semibold)).lineLimit(2)
                HStack(spacing: 5) {
                    Circle().fill(controller.connected ? Color.green : Color.secondary).frame(width: 6, height: 6)
                    Text(controller.status).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let date = controller.connectedAt {
                    HStack(spacing: 4) {
                        Text("Sesja")
                        Text(date, style: .timer).monospacedDigit()
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if controller.connecting || controller.scanning { ProgressView().controlSize(.small) }
        }
    }

    private var batteries: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                battery("Lewa", value: controller.state.left, symbol: "earbud.left", charging: false)
                battery("Prawa", value: controller.state.right, symbol: "earbud.right", charging: false)
                battery("Etui", value: controller.state.caseBattery, symbol: "earbuds.case", charging: controller.state.caseCharging)
            }
            HStack(alignment: .top) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Słuchawki: \(age(controller.state.budsUpdatedAt, now: context.date))")
                        Text("Etui: \(age(controller.state.caseUpdatedAt, now: context.date))")
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { controller.refreshBattery() } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(.plain).help("Ponów odczyt baterii")
                    .accessibilityLabel("Ponów odczyt baterii")
                    .disabled(controller.busy || controller.refreshingBattery || controller.finding != nil)
            }
            if let message = controller.batteryRefreshMessage {
                Text(message).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if controller.state.left == 0 || controller.state.right == 0 {
                Text("0% może oznaczać słuchawkę odłożoną do etui.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func battery(_ label: String, value: Int?, symbol: String, charging: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.map(String.init) ?? "—").font(.system(size: 25, weight: .medium, design: .rounded)).monospacedDigit()
                if value != nil { Text("%").font(.system(size: 11)).foregroundStyle(.secondary) }
                if charging { Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundStyle(.green) }
            }
            GeometryReader { geo in
                Capsule().fill(Color.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill((value ?? 100) < 20 ? Color.orange : accent)
                            .frame(width: geo.size.width * CGFloat(value ?? 0) / 100)
                    }
            }.frame(height: 3)
        }.padding(12).frame(maxWidth: .infinity).background(cardBackground, in: RoundedRectangle(cornerRadius: 13))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value.map { "\($0) procent" } ?? "brak odczytu")\(charging ? ", ładowanie" : "")")
    }

    private func age(_ date: Date?, now: Date) -> String {
        guard let date else { return "brak raportu" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "raport przed chwilą" }
        if seconds < 3600 { return "raport \(seconds / 60) min temu" }
        return "raport \(seconds / 3600) godz. temu"
    }

    private var ancCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Kontrola hałasu", symbol: "waveform.path")
            HStack(spacing: 6) {
                ForEach(ANCMode.allCases) { mode in
                    Button { controller.send(.anc(mode, UInt8(ancLevel))) } label: {
                        VStack(spacing: 7) {
                            Image(systemName: mode == .active ? "waveform" : mode == .off ? "speaker.slash" : "ear.badge.waveform").font(.system(size: 18))
                            Text(mode.title).font(.system(size: 11, weight: .medium))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(controller.state.anc == mode ? Color.black : Color.primary)
                        .background(controller.state.anc == mode ? accent : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).disabled(controller.busy || controller.finding != nil)
                    .accessibilityAddTraits(controller.state.anc == mode ? .isSelected : [])
                    .help(mode == .transparency ? "Tryb transparentny — słyszysz otoczenie" : mode.title)
                }
            }
            if controller.state.anc == .active {
                HStack {
                    Text("Siła ANC").font(.system(size: 11)).foregroundStyle(.secondary)
                    Slider(value: $ancLevel, in: 16...255, step: 1, onEditingChanged: { editing in
                        if !editing { controller.send(.anc(.active, UInt8(ancLevel))) }
                    }).disabled(controller.busy || controller.finding != nil).accessibilityLabel("Siła redukcji hałasu")
                    Text("\(Int((ancLevel - 16) / 239 * 100))%").font(.system(size: 10)).monospacedDigit().frame(width: 32)
                }
            }
            if controller.state.anc == nil {
                Text("Wybierz tryb, aby ustawić ANC. Brak odczytu początkowego.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.card()
    }

    private var soundCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Brzmienie", symbol: "slider.horizontal.3")
            HStack {
                Text("Korektor").font(.system(size: 12))
                Spacer()
                Menu {
                    ForEach(EQPreset.allCases.filter { experimentalEQ || $0 != .clear }) { preset in
                        Button(preset.title) { controller.send(.eq(preset)) }
                    }
                } label: { Text(controller.state.eq?.title ?? "Oczekiwanie…").font(.system(size: 11)) }
                .fixedSize().disabled(controller.busy || controller.finding != nil)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tryb gry").font(.system(size: 12))
                    Text(controller.state.game == nil ? "Niższe opóźnienie · stan nieznany" : "Niższe opóźnienie dźwięku").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                if let game = controller.state.game {
                    Toggle("Tryb gry", isOn: Binding(get: { game }, set: { controller.send(.game($0)) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(controller.busy || controller.finding != nil)
                } else {
                    Menu("Ustaw") {
                        Button("Włącz") { controller.send(.game(true)) }
                        Button("Wyłącz") { controller.send(.game(false)) }
                    }.fixedSize().disabled(controller.busy || controller.finding != nil)
                }
            }
        }.card()
    }

    private var findCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Znajdź słuchawkę", symbol: "location.magnifyingglass")
            if controller.finding != nil {
                Button("Zatrzymaj sygnał") { controller.stopFinding() }.buttonStyle(.borderedProminent).tint(.orange)
            } else {
                HStack {
                    Button { requestedFind = .left; confirmFind = true } label: { Label("Lewa", systemImage: "earbud.left").frame(maxWidth: .infinity) }
                    Button { requestedFind = .right; confirmFind = true } label: { Label("Prawa", systemImage: "earbud.right").frame(maxWidth: .infinity) }
                }.buttonStyle(.bordered).disabled(controller.busy)
            }
            Text("Sygnał dźwiękowy · 5 sekund").font(.system(size: 10)).foregroundStyle(.secondary)
        }.card()
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Twoje słuchawki", symbol: "antenna.radiowaves.left.and.right")
            Text("Otwórz etui i wyjmij słuchawki. Aby odtwarzać dźwięk, sparuj je również w ustawieniach Bluetooth macOS.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(controller.devices) { device in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name).font(.system(size: 12, weight: .medium))
                        Text(device.supported ? (device.rssi == 0 || device.rssi == 127 ? "Dostępne" : "Sygnał \(device.rssi) dBm") : "Model nieobsługiwany")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Połącz") { controller.connect(id: device.id) }.disabled(!device.supported || controller.connecting)
                }
            }
            if controller.connecting || controller.scanning {
                Button("Zatrzymaj") { controller.disconnect() }.buttonStyle(.bordered)
            } else {
                Button { controller.scan(userInitiated: true) } label: { Label("Szukaj słuchawek", systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderedProminent).foregroundStyle(.black)
            }
            Button("Otwórz ustawienia Bluetooth ↗") { openBluetooth() }.buttonStyle(.link).font(.system(size: 11))
            Text("Dostęp: Ustawienia systemowe → Prywatność i ochrona → Bluetooth. Jeśli urządzenie nie odpowiada, zamknij aplikację Baseus na telefonie.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.card()
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Ustawienia", symbol: "gearshape")
            Toggle("Łącz ponownie automatycznie", isOn: $controller.autoReconnect)
            AudioOptions(audio: controller.audio)
            Toggle("Powiadomienia o niskiej baterii", isOn: $controller.batteryAlerts)
            Toggle("Uruchamiaj przy logowaniu", isOn: Binding(get: { login.enabled }, set: { login.setEnabled($0) }))
            if login.usesCompatibility {
                Text("Autostart zapisany — zadziała przy następnym logowaniu.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if login.requiresApproval { Button("Zatwierdź w ustawieniach systemowych") { SMAppService.openSystemSettingsLoginItems() } }
            if let error = login.error { Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            Toggle("Eksperymentalny EQ „Wyrazisty”", isOn: $experimentalEQ)
            Text("Ten preset nie został potwierdzony na sprzęcie w projekcie źródłowym.").font(.system(size: 10)).foregroundStyle(.secondary)
            Divider()
            if let name = controller.preferredName {
                Text("Zapamiętano: \(name)").foregroundStyle(.secondary)
                Button("Zapomnij urządzenie") { controller.forget() }
            }
            Button("Zapisz diagnostykę…") { NotificationCenter.default.post(name: .exportBaseusDiagnostics, object: nil) }
            Button("Ustawienia Bluetooth ↗") { openBluetooth() }
            Link("Protokół: elaxptr/baseus-desktop ↗", destination: URL(string: "https://github.com/elaxptr/baseus-desktop")!)
            Text("Baseus Menu \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") · Niezależna aplikacja\nSwift + CoreBluetooth · Bez telemetrii")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.font(.system(size: 11)).toggleStyle(.switch).controlSize(.small).card()
    }

    private var footer: some View {
        HStack {
            if controller.busy { ProgressView().controlSize(.mini); Text("Potwierdzanie…").font(.system(size: 10)).foregroundStyle(.secondary) }
            else if controller.connected { Button("Rozłącz sterowanie") { controller.disconnect() }.disabled(controller.finding != nil) }
            else { Text("BLE · BP1 Pro ANC").foregroundStyle(.secondary) }
            Spacer()
            Button("Zakończ") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }.font(.system(size: 11)).buttonStyle(.plain).padding(.horizontal, 20).padding(.vertical, 13).background(.bar)
    }

    private var cardBackground: Color { Color(nsColor: .controlBackgroundColor) }
    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.system(size: 12, weight: .semibold))
    }
    private func notice(_ text: String, dismiss: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            Text(text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Zamknij komunikat")
        }.padding(12).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    private func openBluetooth() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!) }
}

private extension View {
    func card() -> some View {
        padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }
}
