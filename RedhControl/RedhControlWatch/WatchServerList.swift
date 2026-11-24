import RedhKit
import RedhUI
import SwiftUI

/// The servers with their state, looked at while the app is on screen. They come from the iPhone;
/// without them, the Watch offers the demo.
struct WatchServerList: View {
    /// The demo while it's tried; set to start it, nil to end it.
    @Binding var demo: Monitor?

    @Environment(Monitor.self) private var monitor

    var body: some View {
        NavigationStack {
            Group {
                if monitor.setup.servers.isEmpty {
                    ContentUnavailableView {
                        Label("No Servers", systemImage: "iphone")
                    } description: {
                        Text("Set up Redh Control on your iPhone; the servers come from there.")
                    } actions: {
                        Button("Try the Demo") { demo = Demo.monitor() }
                    }
                } else {
                    List {
                        ForEach(monitor.setup.servers) { server in
                            NavigationLink(value: server.id) {
                                WatchServerRow(server: server, reading: monitor.readings[server.id])
                            }
                        }
                        if demo != nil {
                            Button("End Demo") { demo = nil }
                        }
                    }
                }
            }
            .navigationTitle(demo == nil ? "Servers" : "Demo")
            .navigationDestination(for: Server.ID.self) { WatchServerDetail(serverID: $0) }
        }
        .refreshing(monitor)
    }
}

struct WatchServerRow: View {
    let server: Server
    let reading: Reading?

    var body: some View {
        HStack(spacing: 10) {
            ServerIconView(server, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(server.name)
                    .font(.headline)
                    .lineLimit(1)
                // No capsule here: "Probably down" in one would not fit the smaller watches.
                StateLine(reading)
                    .font(.footnote.weight(.semibold))
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    WatchServerList(demo: .constant(nil))
        .environment(Demo.monitor())
}
