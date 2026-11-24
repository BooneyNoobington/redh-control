import RedhKit
import RedhUI
import SwiftUI

/// One server: its state, and only the command that makes sense now.
struct WatchServerDetail: View {
    let serverID: Server.ID

    @Environment(Monitor.self) private var monitor
    @State private var confirmsShutdown = false
    @State private var busy = false
    @State private var failure: String?

    var body: some View {
        if let server = monitor.setup.servers.first(where: { $0.id == serverID }) {
            page(server)
        } else {
            ContentUnavailableView("Removed", systemImage: "trash")
        }
    }

    private func page(_ server: Server) -> some View {
        let reading = monitor.readings[server.id]
        let wakeable = monitor.setup.roosterName(for: server) != nil && server.mac != nil && reading?.canWake == true
        return ScrollView {
            VStack(spacing: 10) {
                ServerIconView(server, size: 44)
                StateBadge(reading)
                Text(reading?.summary ?? "Asking RedhAPI…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if wakeable {
                    Button {
                        Task { await run { try await monitor.wake(server) } }
                    } label: {
                        Label(reading?.wakeTitle ?? "Wake Up", systemImage: "sunrise")
                    }
                    .tint(.blue)
                    .disabled(busy)
                }
                if reading?.canShutDown == true {
                    if server.alwaysOn {
                        // A wrist is too easy to tap with: the iPhone asks the rooster first.
                        Text("Always on: shut it down on the iPhone.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Button(role: .destructive) {
                            confirmsShutdown = true
                        } label: {
                            Label("Shut Down", systemImage: "power")
                        }
                        .disabled(busy)
                    }
                }
            }
        }
        .navigationTitle(server.name)
        .confirmationDialog("Shut down \(server.name)?", isPresented: $confirmsShutdown, titleVisibility: .visible) {
            Button("Shut Down", role: .destructive) {
                Task { await run { try await monitor.shutDown(server) } }
            }
        } message: {
            Text(monitor.setup.shutdownNote(for: server))
        }
        .failureAlert($failure)
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
}

#Preview {
    NavigationStack {
        WatchServerDetail(serverID: Demo.setup.servers[0].id)
    }
    .environment(Demo.monitor())
}
