import SwiftUI

#if os(iOS) || os(macOS)
/// What a field holds, so that the iPhone offers the right keyboard.
enum FieldKind {
    case text, url, address, number
}

/// A text field with its label in front, as in Settings. A Mac's form puts the field's own label in
/// front of it; an iPhone's needs it beside the field.
struct FieldRow: View {
    let label: String
    let prompt: String
    @Binding var text: String
    var kind: FieldKind = .text

    var body: some View {
        #if os(macOS)
        TextField(text: $text, prompt: Text(prompt)) {
            Text(label)
        }
        .autocorrectionDisabled()
        #else
        LabeledContent(label) {
            TextField(prompt, text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(kind.keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        #endif
    }
}

/// A password field with its label in front, like ``FieldRow``.
struct SecureRow: View {
    let label: String
    let prompt: String
    @Binding var text: String

    var body: some View {
        #if os(macOS)
        SecureField(text: $text, prompt: Text(prompt)) {
            Text(label)
        }
        #else
        LabeledContent(label) {
            SecureField(prompt, text: $text)
                .multilineTextAlignment(.trailing)
        }
        #endif
    }
}

/// The buttons of a section. A Mac's form shows them as push buttons, side by side in one row; an
/// iPhone's gives each a row of its own, as in Settings.
struct ButtonRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        #if os(macOS)
        HStack {
            content
        }
        #else
        content
        #endif
    }
}

#if os(iOS)
extension FieldKind {
    var keyboard: UIKeyboardType {
        switch self {
        case .text: .default
        case .url: .URL
        case .address: .numbersAndPunctuation
        case .number: .numberPad
        }
    }
}
#endif

/// A problem in the setup, said in a sentence.
struct SetupProblem: LocalizedError {
    let errorDescription: String?

    init(_ description: String) {
        errorDescription = description
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
