import RedhKit
import SwiftUI

#if os(iOS) || os(macOS)
/// A server's apps, as redh-manager lists them: one row per app, then the containers that belong
/// to no app. Without redh-manager, the reason instead.
struct AppsSection: View {
    enum Outcome: Equatable {
        case listed(AppsListing)
        case unavailable(String)
    }

    let outcome: Outcome

    var body: some View {
        switch outcome {
        case .listed(let listing):
            Section {
                ForEach(listing.apps) { app in
                    row(app.name, app.summary, attention: app.installed == "outdated" || app.installed == "orphaned")
                }
                ForEach(listing.containers?.inNoApp ?? [], id: \.name) { container in
                    row(container.name, "\(container.image), in no app", attention: false)
                }
            } header: {
                Text("Apps")
            } footer: {
                Text(([listing.containersSummary] + listing.warnings).joined(separator: " "))
            }
        case .unavailable(let reason):
            Section("Apps") {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ name: String, _ line: String, attention: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
            Text(line)
                .font(.footnote)
                .foregroundStyle(attention ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
    }
}
#endif
