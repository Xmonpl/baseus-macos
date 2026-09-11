import SwiftUI
import AppKit

struct AudioPanel: View {
    @ObservedObject var audio: AudioController
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: audio.ready ? "speaker.wave.2.fill" : "speaker.slash")
                    .foregroundStyle(audio.ready ? Color.green : Color.secondary)
                Text(audio.status).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if audio.working { ProgressView().controlSize(.small) }
            }
            ForEach(audio.choices) { device in
                Button("\(device.name) · \(device.id)") { audio.connect(selectedID: device.id) }
                    .font(.system(size: 10))
            }
            if !audio.ready && !audio.working {
                HStack {
                    Button("Połącz audio") { audio.connect() }
                    Button("Bluetooth ↗") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
                    }
                }.font(.system(size: 11)).buttonStyle(.bordered)
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct AudioOptions: View {
    @ObservedObject var audio: AudioController
    var body: some View {
        Toggle("Łącz audio i wybieraj jako wyjście", isOn: $audio.automatic)
    }
}
