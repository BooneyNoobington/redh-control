import RedhKit
import SwiftUI

#if os(iOS) || os(macOS)
/// A server: its name, where RedhAPI is, its token or pairing code, its rooster and MAC address,
/// its icon.
struct ServerEditor: View {
    private let original: Server?
    private let modal: Bool

    @Environment(Monitor.self) private var monitor
    @Environment(\.dismiss) private var dismiss
    @State private var id: UUID
    @State private var name: String
    @State private var apiURL: String
    @State private var apiURLEdited: Bool
    @State private var token = ""
    /// RedhAPI's own certificate, from a pairing code; nil behind Caddy, with the setup's root.
    @State private var pin: CertificatePin?
    @State private var pairingCode = ""
    @State private var rooster: Rooster?
    @State private var mac: String
    @State private var icon: ServerIcon
    @State private var color: ServerColor
    @State private var alwaysOn: Bool
    @State private var choseRooster = false
    @State private var failure: String?

    /// `modal` adds a Cancel button, for a sheet.
    init(server: Server?, modal: Bool = false) {
        original = server
        self.modal = modal
        _id = State(initialValue: server?.id ?? UUID())
        _name = State(initialValue: server?.name ?? "")
        _apiURL = State(initialValue: server?.apiURL.absoluteString ?? "")
        _apiURLEdited = State(initialValue: server.map { $0.apiURL != Server.defaultAPIURL(for: $0.name) } ?? false)
        _pin = State(initialValue: server?.certificatePin)
        _rooster = State(initialValue: server?.rooster)
        _mac = State(initialValue: server?.mac?.description ?? "")
        _icon = State(initialValue: server?.icon ?? .serverRack)
        _color = State(initialValue: server?.color ?? .blue)
        _alwaysOn = State(initialValue: server?.alwaysOn ?? false)
    }

    var body: some View {
        Form {
            Section {
                ServerIconView(icon: icon, color: color, size: 64)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
            Section {
                FieldRow(label: "Name", prompt: "nas", text: $name)
                FieldRow(label: "RedhAPI", prompt: pin == nil ? "https://rapi.nas.internal" : "https://192.168.1.10:8470",
                         text: apiURLBinding, kind: .url)
                SecureRow(label: "Token", prompt: hasToken ? "Saved" : "From redh-api token", text: $token)
                FieldRow(label: "Pairing code", prompt: "redh1:…", text: $pairingCode)
            } header: {
                Text("Server")
            } footer: {
                if !pairingCode.isEmpty {
                    Text("That's no pairing code yet: it's one line, from 'redh-api token', starting with redh1:.")
                } else {
                    Text("The token is the one 'redh-api token' printed on the server. Without it, Redh Control only sees whether RedhAPI answers. Where RedhAPI has a certificate of its own, it prints a pairing code too: paste that instead, as it holds the token and the certificate.")
                }
            }
            Section {
                if let pin {
                    LabeledContent("Trusted", value: "RedhAPI's own")
                    Fingerprint(pin: pin)
                    Button("Forget the Pairing") { self.pin = nil }
                } else {
                    LabeledContent("Trusted", value: "From your CA")
                }
            } header: {
                Text("Certificate")
            } footer: {
                Text(pin == nil
                     ? "Behind Caddy, RedhAPI's certificate comes from your CA, whose root is in the setup."
                     : "Paired: Redh Control trusts this certificate alone, under any name or address of the server.")
            }
            Section {
                Picker("Rooster", selection: $rooster) {
                    Text("None").tag(Rooster?.none)
                    if !monitor.setup.boxes.isEmpty {
                        Section("FRITZ!Boxes") {
                            ForEach(monitor.setup.boxes) { box in
                                Text(box.name).tag(Rooster?.some(.box(box.id)))
                            }
                        }
                    }
                    if !otherServers.isEmpty {
                        Section("Servers") {
                            ForEach(otherServers) { server in
                                Text(server.name).tag(Rooster?.some(.server(server.id)))
                            }
                        }
                    }
                }
                FieldRow(label: "MAC address", prompt: "AA:BB:CC:DD:EE:FF", text: $mac)
            } header: {
                Text("Waking Up")
            } footer: {
                Text("The rooster wakes the server up, by the address of its network card: a FRITZ!Box, or another server that stays on, through its RedhAPI.")
            }
            Section {
                Toggle("Always on", isOn: $alwaysOn)
            } footer: {
                Text("For a server that should keep running. Shutting it down asks once more, after asking its rooster whether it could wake it up again. The Watch doesn't offer Shut Down for it.")
            }
            Section("Icon") {
                IconPicker(icon: $icon, color: $color)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(original?.name ?? "New Server")
        .toolbar {
            if modal {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!isComplete)
            }
        }
        .onChange(of: name) {
            // Behind Caddy, RedhAPI's address follows the name; paired, it's the server's own.
            if !apiURLEdited, pin == nil {
                apiURL = Server.defaultAPIURL(for: name)?.absoluteString ?? ""
            }
        }
        .onChange(of: pairingCode) {
            guard let code = PairingCode(pairingCode) else { return }
            token = code.token
            pin = code.pin
            pairingCode = ""
            if !apiURLEdited {
                apiURL = ""  // rapi.NAME.internal is Caddy's: the address is the server's own now
            }
        }
        .onAppear {
            // A new server is most likely woken by the first box, if there is one.
            if original == nil, !choseRooster {
                choseRooster = true
                rooster = monitor.setup.boxes.first.map { .box($0.id) }
            }
        }
        .failureAlert($failure)
    }

    /// The address as typed; once typed, it no longer follows the name.
    private var apiURLBinding: Binding<String> {
        Binding {
            apiURL
        } set: {
            apiURL = $0
            apiURLEdited = true
        }
    }

    /// The servers that can be this one's rooster: all but itself.
    private var otherServers: [Server] {
        monitor.setup.servers.filter { $0.id != id }
    }

    private var hasToken: Bool {
        monitor.hasSecret(.token(server: id))
    }

    private var isComplete: Bool {
        guard !name.trimmed.isEmpty, let url = URL(string: apiURL.trimmed), url.scheme == "https", url.host() != nil
        else { return false }
        return mac.trimmed.isEmpty || MACAddress(mac) != nil
    }

    private func save() {
        guard let url = URL(string: apiURL.trimmed) else { return }
        let server = Server(id: id, name: name.trimmed, apiURL: url, certificatePin: pin, rooster: rooster,
                            mac: MACAddress(mac), icon: icon, color: color, alwaysOn: alwaysOn)
        do {
            try monitor.save(server, token: token.isEmpty ? nil : token)
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        ServerEditor(server: nil)
    }
    .environment(Demo.monitor())
}
#endif
