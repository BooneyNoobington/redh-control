import RedhKit
import RedhUI
import SwiftUI

@main
struct RedhControlMacApp: App {
    @State private var start = Start.load()
    /// The demo homelab, while someone tries it in place of the setup, as App Review does.
    @State private var demo: Monitor?

    var body: some Scene {
        WindowGroup {
            switch start {
            case .ready(let monitor):
                if let demo {
                    ServerBrowser(open: nil, demo: $demo)
                        .environment(demo)
                } else {
                    ServerBrowser(open: LaunchOptions.value(after: "-open"), demo: $demo)
                        .environment(monitor)
                }
            case .failed(let message):
                ContentUnavailableView("The Setup Can't Be Read", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            }
        }
        .defaultSize(width: 920, height: 660)
    }
}

/// What the app starts with: the monitor, or why there is none. The Mac keeps a setup of its own,
/// with its own tokens, in its own Keychain.
enum Start {
    case ready(Monitor)
    case failed(String)

    static func load() -> Start {
        do {
            return .ready(try Monitor.forLaunch())
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
