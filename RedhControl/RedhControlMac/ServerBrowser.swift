import RedhKit
import RedhUI
import SwiftUI

/// The servers in a sidebar, each with its state, and the chosen one's page beside them. While the
/// window is in front, the servers are looked at every 10 seconds, every 3 while a command waits for
/// its effect. Without servers, it offers the setup and the demo.
struct ServerBrowser: View {
    let open: String?
    /// The demo while it's tried; set to start it, nil to end it.
    @Binding var demo: Monitor?

    @Environment(Monitor.self) private var monitor
    @State private var selection: Server.ID?
    @State private var showsSetup = false
    @State private var opened = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(monitor.setup.servers) { server in
                    HStack(spacing: 10) {
                        ServerIconView(server, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name)
                            StateLine(monitor.readings[server.id])
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(server.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .overlay {
                if monitor.setup.servers.isEmpty {
                    ContentUnavailableView {
                        Label("No Servers Yet", systemImage: "server.rack")
                    } description: {
                        Text("Set up your CA's root certificate and your servers, each running RedhAPI. Or try the app first, with a made-up homelab.")
                    } actions: {
                        Button("Open Setup") { showsSetup = true }
                        Button("Try the Demo") { demo = Demo.monitor() }
                    }
                }
            }
        } detail: {
            if let selection, monitor.setup.servers.contains(where: { $0.id == selection }) {
                ServerDetail(serverID: selection)
                    .id(selection)
            } else {
                ContentUnavailableView("No Server Chosen", systemImage: "sidebar.left",
                                       description: Text("Pick one on the left."))
            }
        }
        .toolbar {
            if demo != nil {
                ToolbarItem {
                    Button("End Demo") { demo = nil }
                }
            }
            ToolbarItem {
                Button("Setup", systemImage: "gearshape") { showsSetup = true }
            }
        }
        .sheet(isPresented: $showsSetup) {
            SetupView()
        }
        .refreshing(monitor)
        .onAppear(perform: openOnce)
    }

    /// `-open NAME` picks that server, `-open setup` opens the setup; otherwise the first server,
    /// also in the demo.
    private func openOnce() {
        guard !opened else { return }
        opened = true
        if open == "setup" {
            showsSetup = true
        }
        selection = monitor.setup.servers.first { $0.name == open }?.id ?? monitor.setup.servers.first?.id
    }
}
