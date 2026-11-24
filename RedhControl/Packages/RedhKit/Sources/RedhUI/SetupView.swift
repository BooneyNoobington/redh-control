import RedhKit
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS) || os(macOS)
/// The CA's root certificate, the FRITZ!Boxes and the servers. `-box NAME` at launch opens that
/// box's editor, for screenshots.
public struct SetupView: View {
    @Environment(Monitor.self) private var monitor
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Page] = []
    @State private var openedAtLaunch = false
    @State private var importsCertificate = false
    @State private var failure: String?

    /// An editor the setup opens: for a box or a server, nil for a new one.
    enum Page: Hashable {
        case box(Box.ID?)
        case server(Server.ID?)
    }

    public init() {}

    public var body: some View {
        NavigationStack(path: $path) {
            Form {
                certificate
                Section {
                    ForEach(monitor.setup.boxes) { box in
                        NavigationLink(value: Page.box(box.id)) {
                            LabeledContent(box.name, value: box.host)
                        }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                perform { try monitor.remove(box) }
                            }
                        }
                    }
                    .onDelete { offsets in
                        let boxes = offsets.map { monitor.setup.boxes[$0] }
                        perform {
                            for box in boxes {
                                try monitor.remove(box)
                            }
                        }
                    }
                    NavigationLink(value: Page.box(nil)) {
                        Label("Add FRITZ!Box", systemImage: "plus")
                    }
                } header: {
                    Text("FRITZ!Boxes")
                } footer: {
                    Text("A FRITZ!Box can be the rooster of servers: it wakes them up, and sees whether they're on the network. Without one, a server that stays on can be the rooster.")
                }
                Section("Servers") {
                    ForEach(monitor.setup.servers) { server in
                        NavigationLink(value: Page.server(server.id)) {
                            Label {
                                Text(server.name)
                            } icon: {
                                ServerIconView(server, size: 28)
                            }
                        }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                perform { try monitor.remove(server) }
                            }
                        }
                    }
                    .onDelete { offsets in
                        let servers = offsets.map { monitor.setup.servers[$0] }
                        perform {
                            for server in servers {
                                try monitor.remove(server)
                            }
                        }
                    }
                    NavigationLink(value: Page.server(nil)) {
                        Label("Add Server", systemImage: "plus")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .box(let id): BoxEditor(box: monitor.setup.boxes.first { $0.id == id })
                case .server(let id): ServerEditor(server: monitor.setup.servers.first { $0.id == id })
                }
            }
            .navigationTitle("Setup")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(isPresented: $importsCertificate, allowedContentTypes: [.x509Certificate, .data]) { result in
                perform {
                    let url = try result.get()
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessing {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    try useCertificate(Data(contentsOf: url), from: url.lastPathComponent)
                }
            }
            .failureAlert($failure)
            .onAppear(perform: openBoxOnce)
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 560, idealHeight: 640)
        #endif
    }

    private var certificate: some View {
        Section {
            if let der = monitor.setup.rootCertificate {
                LabeledContent("Root", value: RootCertificate.summary(of: der) ?? "Unreadable")
                Fingerprint(pin: CertificatePin(certificate: der))
            }
            ButtonRow {
                Button(monitor.setup.rootCertificate == nil ? "Import Root Certificate…" : "Replace Root Certificate…") {
                    importsCertificate = true
                }
                PasteButton(payloadType: String.self) { texts in
                    perform { try useCertificate(Data((texts.first ?? "").utf8), from: "The clipboard") }
                }
            }
        } header: {
            Text("Certificate Authority")
        } footer: {
            Text("Behind Caddy, RedhAPI's certificates come from your ACME CA: Redh Control trusts its root for them, and nothing else. Import the root certificate as a file, or copy it as PEM and paste it. Servers paired with RedhAPI's own certificate don't need it.")
        }
    }

    private func openBoxOnce() {
        guard !openedAtLaunch else { return }
        openedAtLaunch = true
        if let name = LaunchOptions.value(after: "-box"), let box = monitor.setup.boxes.first(where: { $0.name == name }) {
            path = [.box(box.id)]
        }
    }

    private func useCertificate(_ data: Data, from source: String) throws {
        guard let der = RootCertificate.der(from: data) else { throw SetupProblem("\(source) holds no certificate.") }
        try monitor.setRootCertificate(der)
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            failure = error.localizedDescription
        }
    }
}

#Preview {
    SetupView()
        .environment(Demo.monitor())
}
#endif
