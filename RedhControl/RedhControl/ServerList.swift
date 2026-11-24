import RedhKit
import RedhUI
import SwiftUI

/// The servers, each with its state. While the app is in front, they are looked at every 10
/// seconds, and every 3 while a command waits for its effect. Without servers, it offers the setup
/// and the demo.
struct ServerList: View {
    let open: String?
    /// The demo while it's tried; set to start it, nil to end it.
    @Binding var demo: Monitor?

    @Environment(Monitor.self) private var monitor
    @State private var path: [Server.ID] = []
    @State private var showsSetup = false
    @State private var opened = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(demo == nil ? "Servers" : "Demo")
                .navigationDestination(for: Server.ID.self) { ServerDetail(serverID: $0) }
                .toolbar {
                    if demo != nil {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("End Demo") { demo = nil }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Setup", systemImage: "gearshape") { showsSetup = true }
                    }
                }
        }
        .sheet(isPresented: $showsSetup) {
            SetupView()
        }
        .refreshing(monitor)
        .onAppear(perform: openOnce)
    }

    @ViewBuilder
    private var content: some View {
        if monitor.setup.servers.isEmpty {
            ContentUnavailableView {
                Label("No Servers Yet", systemImage: "server.rack")
            } description: {
                Text("Set up your CA's root certificate and your servers, each running RedhAPI. Or try the app first, with a made-up homelab.")
            } actions: {
                Button("Set Up") { showsSetup = true }
                    .buttonStyle(.borderedProminent)
                Button("Try the Demo") { demo = Demo.monitor() }
            }
        } else {
            List(monitor.setup.servers) { server in
                NavigationLink(value: server.id) {
                    ServerRow(server: server, reading: monitor.readings[server.id])
                }
            }
            .refreshable { await monitor.refresh() }
        }
    }

    private func openOnce() {
        guard !opened, let open else { return }
        opened = true
        if open == "setup" {
            showsSetup = true
        } else if let server = monitor.setup.servers.first(where: { $0.name == open }) {
            path = [server.id]
        }
    }
}

struct ServerRow: View {
    let server: Server
    let reading: Reading?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ServerIconView(server)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(server.name)
                        .font(.headline)
                    Spacer(minLength: 8)
                    StateBadge(reading)
                }
                // Under the name and the badge, the summary has the whole width.
                Text(reading?.summary ?? "Asking RedhAPI…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ServerList(open: nil, demo: .constant(nil))
        .environment(Demo.monitor())
}
