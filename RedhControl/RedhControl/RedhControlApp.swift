import RedhKit
import SwiftUI

@main
struct RedhControlApp: App {
    @State private var start = Start.load()
    /// The demo homelab, while someone tries it in place of the setup, as App Review does.
    @State private var demo: Monitor?

    var body: some Scene {
        WindowGroup {
            switch start {
            case .ready(let monitor, let link):
                if let demo {
                    ServerList(open: nil, demo: $demo)
                        .environment(demo)
                } else {
                    ServerList(open: LaunchOptions.value(after: "-open"), demo: $demo)
                        .environment(monitor)
                        .onChange(of: monitor.revision) { link?.send() }
                }
            case .failed(let message):
                ContentUnavailableView("The Setup Can't Be Read", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            }
        }
    }
}

/// What the app starts with: the monitor, and the link that sends its setup to the Watch.
enum Start {
    case ready(Monitor, WatchLink?)
    case failed(String)

    static func load() -> Start {
        do {
            let monitor = try Monitor.forLaunch()
            // The demo stays on the iPhone: it would replace the Watch's setup.
            let link = LaunchOptions.has("-demo") ? nil : WatchLink(monitor: monitor)
            link?.activate()
            return .ready(monitor, link)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
