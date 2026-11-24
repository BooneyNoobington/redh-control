import RedhKit
import SwiftUI

#if os(iOS) || os(macOS)
/// One server: its state, the two commands, what RedhAPI reports, its apps, and its setup.
public struct ServerDetail: View {
    let serverID: Server.ID

    public init(serverID: Server.ID) {
        self.serverID = serverID
    }

    @Environment(Monitor.self) private var monitor
    @State private var confirmsShutdown = false
    /// For an always-on server: what its rooster said, to ask once more.
    @State private var wakeCheck: WakeCheck?
    @State private var apps: AppsSection.Outcome?
    @State private var system: SystemReport?
    @State private var editing = false
    @State private var editedAtLaunch = false
    @State private var busy = false
    @State private var failure: String?

    public var body: some View {
        if let server = monitor.setup.servers.first(where: { $0.id == serverID }) {
            page(server)
        } else {
            ContentUnavailableView("Removed", systemImage: "trash")
        }
    }

    private func page(_ server: Server) -> some View {
        let reading = monitor.readings[server.id]
        let rooster = monitor.setup.roosterName(for: server)
        return Form {
            Section {
                VStack(spacing: 10) {
                    ServerIconView(server, size: 72)
                    StateBadge(reading)
                    Text(reading?.summary ?? "Asking RedhAPI…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                ButtonRow {
                    command(reading?.wakeTitle ?? "Wake Up", systemImage: "sunrise", color: .blue,
                            enabled: !busy && rooster != nil && server.mac != nil && reading?.canWake != false) {
                        Task { await run { try await monitor.wake(server) } }
                    }
                    command("Shut Down", systemImage: "power", color: .red,
                            enabled: !busy && reading?.canShutDown == true) {
                        confirmsShutdown = true
                    }
                }
            } footer: {
                if let hint = hint(for: server, reading: reading) {
                    Text(hint)
                }
            }
            if case .up(let status)? = reading?.state {
                Section("RedhAPI") {
                    LabeledContent("Version", value: status.version)
                    if let uptime = status.uptimeSeconds {
                        LabeledContent("Running for", value: uptimeText(uptime))
                    }
                    LabeledContent("Shutdown", value: status.shutdown.ready ? "Ready" : "Not ready")
                    if let problem = status.shutdown.problem {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let system {
                    SystemSection(report: system)
                }
                if let apps {
                    AppsSection(outcome: apps)
                }
            }
            Section("Setup") {
                LabeledContent("RedhAPI", value: server.apiURL.absoluteString)
                LabeledContent("Certificate", value: server.certificatePin == nil ? "From your CA" : "RedhAPI's own, paired")
                LabeledContent("Rooster", value: rooster ?? "None")
                LabeledContent("MAC address", value: server.mac?.description ?? "None")
                LabeledContent("Always on", value: server.alwaysOn ? "Yes" : "No")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(server.name)
        .toolbar {
            Button("Edit") { editing = true }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                ServerEditor(server: server, modal: true)
            }
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 520, minHeight: 560, idealHeight: 640)
            #endif
        }
        .onAppear {
            if LaunchOptions.has("-edit"), !editedAtLaunch {
                editedAtLaunch = true
                editing = true
            }
        }
        .task(id: "\(server.id) \(reading?.isUp == true)") {
            await lookAt(server, up: reading?.isUp == true)
        }
        .confirmationDialog("Shut down \(server.name)?", isPresented: $confirmsShutdown, titleVisibility: .visible) {
            Button("Shut Down", role: .destructive) {
                Task {
                    if server.alwaysOn {
                        await askRooster(about: server)
                    } else {
                        await run { try await monitor.shutDown(server) }
                    }
                }
            }
        } message: {
            Text(monitor.setup.shutdownNote(for: server))
        }
        .alert("Shut down \(server.name) anyway?", isPresented: asksOnceMore, presenting: wakeCheck) { _ in
            Button("Shut Down Anyway", role: .destructive) {
                Task { await run { try await monitor.shutDown(server) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { check in
            Text("\(server.name) is meant to be always on. \(check.explanation)")
        }
        .failureAlert($failure)
    }

    /// While the server is up, what its machine is doing and its apps, every 10 seconds: RedhAPI
    /// keeps its readings for 5 seconds, and redh's answer for 10.
    private func lookAt(_ server: Server, up: Bool) async {
        guard up else {
            apps = nil
            system = nil
            return
        }
        while !Task.isCancelled {
            async let report = try? monitor.system(of: server)  // nil from a RedhAPI before 0.2.0
            async let listing = appsOutcome(of: server)
            (system, apps) = await (report, listing)
            try? await Task.sleep(for: .seconds(10))
        }
    }

    private func appsOutcome(of server: Server) async -> AppsSection.Outcome? {
        do {
            return .listed(try await monitor.apps(of: server))
        } catch RedhAPIError.appsUnavailable(let reason) {
            return .unavailable(reason)
        } catch {
            return nil  // an older RedhAPI without /v1/apps, or no answer: the page says enough
        }
    }

    private var asksOnceMore: Binding<Bool> {
        Binding {
            wakeCheck != nil
        } set: {
            if !$0 {
                wakeCheck = nil
            }
        }
    }

    /// Before an always-on server is shut down: could its rooster wake it up again?
    private func askRooster(about server: Server) async {
        busy = true
        defer { busy = false }
        wakeCheck = await monitor.wakeCheck(server)
    }

    /// A command button, grey when the command makes no sense: a disabled button in a list keeps
    /// its colored icon otherwise.
    private func command(_ title: String, systemImage: String, color: Color, enabled: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(enabled ? color : .secondary)
        }
        .disabled(!enabled)
    }

    private func run(_ command: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await command()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func hint(for server: Server, reading: Reading?) -> String? {
        if monitor.setup.roosterName(for: server) == nil {
            return "It has no rooster, so it can't be woken up."
        }
        if server.mac == nil {
            return "Without its MAC address, it can't be woken up."
        }
        if reading?.canWake == true, let rooster = monitor.setup.roosterServer(for: server),
           monitor.readings[rooster.id]?.answers == false {
            return "Its rooster \(rooster.name) doesn't answer: wake \(rooster.name) up first."
        }
        if case .up(let status)? = reading?.state, !status.shutdown.ready {
            return "RedhAPI can't shut it down yet."
        }
        return nil
    }
}

#Preview {
    NavigationStack {
        ServerDetail(serverID: Demo.setup.servers[0].id)
    }
    .environment(Demo.monitor())
}
#endif
