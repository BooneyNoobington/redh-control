import RedhKit
import SwiftUI

#if os(iOS) || os(macOS)
/// The server's SF Symbol and color, picked from grids.
struct IconPicker: View {
    @Binding var icon: ServerIcon
    @Binding var color: ServerColor

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ServerIcon.allCases, id: \.self) { candidate in
                    let selected = candidate == icon
                    Button {
                        icon = candidate
                    } label: {
                        Image(systemName: candidate.symbolName)
                            .font(.title3)
                            .foregroundStyle(selected ? Color.white : color.color)
                            .frame(width: 44, height: 44)
                            .background(selected ? AnyShapeStyle(color.color.gradient) : AnyShapeStyle(.fill.tertiary),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(candidate.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(ServerColor.allCases, id: \.self) { candidate in
                    Button {
                        color = candidate
                    } label: {
                        Circle()
                            .fill(candidate.color.gradient)
                            .frame(width: 28, height: 28)
                            .padding(4)
                            .overlay {
                                if candidate == color {
                                    Circle().strokeBorder(.primary, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(candidate.rawValue)
                    .accessibilityAddTraits(candidate == color ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 8)
    }
}
#endif
