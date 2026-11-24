import RedhKit
import SwiftUI

@main
struct RedhControlWatchApp: App {
    @State private var start = WatchStart.load()
    /// The demo homelab, while someone tries it in place of the iPhone's setup, as App Review does.
    @State private var demo: Monitor?

    var body: some Scene {
        WindowGroup {
            switch start {
            case .ready(let monitor, _):
                WatchServerList(demo: $demo)
                    .environment(demo ?? monitor)
            case .failed(let message):
                ContentUnavailableView("The Setup Can't Be Read", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            }
        }
    }
}

/// What the app starts with: the monitor, and the link through which the iPhone keeps its setup
/// current.
enum WatchStart {
    case ready(Monitor, WatchLink?)
    case failed(String)

    static func load() -> WatchStart {
        do {
            let monitor = try Monitor.forLaunch()
            // The demo stays the demo: nothing from the iPhone replaces it.
            let link = LaunchOptions.has("-demo") ? nil : WatchLink(monitor: monitor)
            link?.activate()
            return .ready(monitor, link)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
