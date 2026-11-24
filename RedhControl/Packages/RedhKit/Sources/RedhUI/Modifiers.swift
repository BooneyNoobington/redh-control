import RedhKit
import SwiftUI

extension View {
    /// Looks at the servers while the app is in front: every 10 seconds, every 3 while a command
    /// waits for its effect.
    public func refreshing(_ monitor: Monitor) -> some View {
        modifier(Refreshing(monitor: monitor))
    }

    /// Shows the failure's message until it is dismissed.
    public func failureAlert(_ failure: Binding<String?>) -> some View {
        alert("That Didn't Work", isPresented: Binding { failure.wrappedValue != nil } set: { if !$0 { failure.wrappedValue = nil } }) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure.wrappedValue ?? "")
        }
    }
}

private struct Refreshing: ViewModifier {
    let monitor: Monitor
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await monitor.refresh()
                try? await Task.sleep(for: .seconds(monitor.isWaiting ? 3 : 10))
            }
        }
    }
}
