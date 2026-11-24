import RedhKit
import SwiftUI

extension ServerColor {
    public var color: Color {
        switch self {
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .mint: .mint
        case .yellow: .yellow
        case .orange: .orange
        case .red: .red
        case .pink: .pink
        case .purple: .purple
        case .indigo: .indigo
        case .brown: .brown
        case .gray: .gray
        }
    }
}

extension Tone {
    public var color: Color {
        switch self {
        case .up: .green
        case .caution: .orange
        case .down: .secondary
        case .unknown: .gray
        case .busy: .blue
        }
    }
}

/// A server's SF Symbol, in white on its color, to tell servers apart at a glance.
public struct ServerIconView: View {
    let icon: ServerIcon
    let color: ServerColor
    let size: CGFloat

    public init(icon: ServerIcon, color: ServerColor, size: CGFloat = 36) {
        self.icon = icon
        self.color = color
        self.size = size
    }

    public init(_ server: Server, size: CGFloat = 36) {
        self.init(icon: server.icon, color: server.color, size: size)
    }

    public var body: some View {
        Image(systemName: icon.symbolName)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityLabel(icon.label)
    }
}

/// The state of a server as a symbol and a few words, in its color; "Checking" before the first
/// look. On its own, for narrow rows such as the Watch's; ``StateBadge`` puts it in a capsule.
public struct StateLine: View {
    let reading: Reading?

    @Environment(\.backgroundProminence) private var backgroundProminence

    public init(_ reading: Reading?) {
        self.reading = reading
    }

    public var body: some View {
        // Not a Label: in a list, a Label keeps a column free for its icon.
        HStack(spacing: 4) {
            Image(systemName: reading?.symbolName ?? "ellipsis.circle.fill")
            Text(reading?.title ?? "Checking")
        }
        .lineLimit(1)
        .foregroundStyle(style)
        .accessibilityElement(children: .combine)
    }

    /// The state's color, except on a selected row such as in the Mac's sidebar, where it would
    /// be hard to read: the secondary style turns white there.
    private var style: AnyShapeStyle {
        backgroundProminence == .increased ? AnyShapeStyle(.secondary) : AnyShapeStyle(reading?.tone.color ?? .gray)
    }
}

/// The state of a server as a small capsule.
public struct StateBadge: View {
    let reading: Reading?

    public init(_ reading: Reading?) {
        self.reading = reading
    }

    public var body: some View {
        StateLine(reading)
            .font(.caption.weight(.semibold))
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((reading?.tone.color ?? .gray).opacity(0.15), in: Capsule())
    }
}
