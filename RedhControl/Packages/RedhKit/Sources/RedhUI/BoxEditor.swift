import RedhKit
import SwiftUI

#if os(iOS) || os(macOS)
/// A FRITZ!Box: where it is, the login, and its pinned certificate.
struct BoxEditor: View {
    private let original: Box?

    @Environment(Monitor.self) private var monitor
    @Environment(\.dismiss) private var dismiss
    @State private var id: UUID
    @State private var name: String
    @State private var host: String
    @State private var fallbackAddress: String
    @State private var port: String
    @State private var username: String
    @State private var password = ""
    @State private var pin: CertificatePin?
    @State private var presented: CertificatePin?
    @State private var fetching = false
    @State private var failure: String?

    init(box: Box?) {
        original = box
        _id = State(initialValue: box?.id ?? UUID())
        _name = State(initialValue: box?.name ?? "")
        _host = State(initialValue: box?.host ?? "")
        _fallbackAddress = State(initialValue: box?.fallbackAddress ?? "")
        _port = State(initialValue: String(box?.port ?? Box.defaultPort))
        _username = State(initialValue: box?.username ?? "")
        _pin = State(initialValue: box?.certificatePin)
    }

    var body: some View {
        Form {
            Section("FRITZ!Box") {
                FieldRow(label: "Name", prompt: "lab-box", text: $name)
                FieldRow(label: "Host", prompt: "fritz.lab.internal", text: $host, kind: .url)
                FieldRow(label: "IP address", prompt: "optional", text: $fallbackAddress, kind: .address)
                FieldRow(label: "Port", prompt: "49443", text: $port, kind: .number)
            }
            Section {
                FieldRow(label: "User", prompt: "FRITZ!Box user", text: $username)
                SecureRow(label: "Password", prompt: hasPassword ? "Saved" : "Required", text: $password)
            } header: {
                Text("Login")
            } footer: {
                Text("A FRITZ!Box user of its own for Redh Control is best. The box needs \"Allow access for applications\" (TR-064) turned on.")
            }
            Section {
                if let pin {
                    Fingerprint(pin: pin)
                }
                if let presented, presented != pin {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The box presents this certificate:")
                        Fingerprint(pin: presented)
                    }
                    Button("Trust This Certificate") {
                        pin = presented
                        self.presented = nil
                    }
                }
                Button(pin == nil ? "Fetch Certificate" : "Fetch Again") {
                    Task { await fetch() }
                }
                .disabled(fetching || host.trimmed.isEmpty)
            } header: {
                Text("Certificate")
            } footer: {
                Text("The box signs its certificate itself, so Redh Control remembers it, as SSH does with host keys. Fetch it on your own network.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(original?.name ?? "New FRITZ!Box")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!isComplete)
            }
        }
        .failureAlert($failure)
    }

    private var draft: Box {
        let address = fallbackAddress.trimmed
        return Box(id: id, name: name.trimmed, host: host.trimmed, fallbackAddress: address.isEmpty ? nil : address,
                   port: Int(port) ?? Box.defaultPort, username: username.trimmed, certificatePin: pin)
    }

    private var hasPassword: Bool {
        monitor.hasSecret(.password(box: id))
    }

    private var isComplete: Bool {
        !name.trimmed.isEmpty && !host.trimmed.isEmpty && !username.trimmed.isEmpty
            && Int(port).map { (1...65535).contains($0) } == true
            && (hasPassword || !password.isEmpty)
    }

    private func fetch() async {
        fetching = true
        defer { fetching = false }
        do {
            presented = try await monitor.presentedCertificate(of: draft)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func save() {
        do {
            try monitor.save(draft, password: password.isEmpty ? nil : password)
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// A certificate's SHA-256, small and selectable, to compare it: two lines of 16 bytes, so that
/// no byte is split.
struct Fingerprint: View {
    let pin: CertificatePin

    var body: some View {
        let bytes = pin.description.split(separator: ":")
        VStack(alignment: .leading, spacing: 2) {
            Text(bytes.prefix(16).joined(separator: ":"))
            Text(bytes.dropFirst(16).joined(separator: ":"))
        }
        .font(.caption2.monospaced())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
}

#Preview {
    NavigationStack {
        BoxEditor(box: Demo.setup.boxes[0])
    }
    .environment(Demo.monitor())
}
#endif
