import AppKit
import SwiftUI

struct ToolCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(12)
        .background(Color.whyCardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct EditorPairView: View {
    let leftTitle: String
    let rightTitle: String
    @Binding var leftText: String
    @Binding var rightText: String

    var body: some View {
        HStack(spacing: 12) {
            ToolCard(title: leftTitle) {
                TextEditor(text: $leftText)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .frame(minHeight: 290)
            }
            ToolCard(title: rightTitle) {
                TextEditor(text: $rightText)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .frame(minHeight: 290)
            }
        }
    }
}

struct ActionButtonRow: View {
    let actions: [ActionItem]

    struct ActionItem: Identifiable {
        let id = UUID()
        let title: String
        let role: ButtonRole?
        let action: () -> Void

        init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
            self.title = title
            self.role = role
            self.action = action
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(actions) { item in
                    Button(item.title, role: item.role, action: item.action)
                        .buttonStyle(.borderedProminent)
                        .tint(item.role == .destructive ? .red : .teal)
                }
            }
        }
    }
}

struct StatusLine: View {
    let text: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .red : .teal)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isError ? .red : .secondary)
            Spacer()
        }
        .padding(.horizontal, 2)
    }
}

func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
