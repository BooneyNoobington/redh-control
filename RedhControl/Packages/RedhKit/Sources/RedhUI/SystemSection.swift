import RedhKit
import SwiftUI

#if os(iOS) || os(macOS)
/// What a server's machine is doing, as its RedhAPI reports it: one row per meter, with a bar where
/// something can fill up. The footer says when tasks had to wait, and why there is no power.
struct SystemSection: View {
    let report: SystemReport

    var body: some View {
        let meters = report.meters()
        if !meters.isEmpty {
            Section {
                ForEach(meters) { meter in
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent(meter.name, value: meter.value)
                        if let fraction = meter.fraction {
                            ProgressView(value: min(max(fraction, 0), 1))
                                .tint(tint(fraction))
                                .accessibilityHidden(true)
                        }
                    }
                }
            } header: {
                Text("System")
            } footer: {
                if !report.notes.isEmpty {
                    Text(report.notes.joined(separator: " "))
                }
            }
        }
    }

    /// Orange from three quarters, red from nine tenths.
    private func tint(_ fraction: Double) -> Color {
        fraction >= 0.9 ? .red : fraction >= 0.75 ? .orange : .accentColor
    }
}
#endif
