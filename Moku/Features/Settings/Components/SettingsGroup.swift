import SwiftUI

struct SettingsGroup<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: () -> Content
    init(_ title: String, symbol: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, phosphor: symbol).font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(spacing: 0, content: content)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(NavigationStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(
                        .white.opacity(0.09), lineWidth: 0.5)
                }
        }
    }
}
