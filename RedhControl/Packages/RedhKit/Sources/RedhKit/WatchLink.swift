#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity

/// Keeps the Watch's setup the iPhone's. The iPhone sends its setup and secrets as the
/// application context whenever they change, and the Watch puts the latest into place. Keep a
/// reference: the session holds its delegate weakly.
@MainActor
public final class WatchLink: NSObject {
    nonisolated static let key = "sync"
    private let monitor: Monitor

    public init(monitor: Monitor) {
        self.monitor = monitor
    }

    public func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// On the iPhone: sends the setup and secrets as they are now, if a Watch with the app is
    /// there. If sending fails, the next change sends again.
    public func send() {
        #if os(iOS)
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        guard let data = try? WatchSync(setup: monitor.setup, secrets: monitor.secrets).data() else { return }
        try? session.updateApplicationContext([Self.key: data])
        #endif
    }

    /// On the Watch: puts what the iPhone sent into place.
    func receive(_ data: Data?) {
        #if os(watchOS)
        guard let data, let sync = try? WatchSync(data: data) else { return }
        try? sync.apply(to: monitor)
        #endif
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                                    error: Error?) {
        let data = session.receivedApplicationContext[WatchLink.key] as? Data
        Task { @MainActor in
            #if os(iOS)
            self.send()
            #else
            self.receive(data)
            #endif
        }
    }

    nonisolated public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext[WatchLink.key] as? Data
        Task { @MainActor in self.receive(data) }
    }

    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Another Watch was paired: start over with that one.
    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// The app may just have been installed on the Watch.
    nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.send() }
    }
    #endif
}
#endif
