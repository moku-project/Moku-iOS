import SwiftUI

struct HomeSection<Content: View>: View {
    let title: String
    var systemImage: String?
    var trailing: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).imageScale(.small).accessibilityHidden(true)
                }
                Text(title).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing).foregroundStyle(.tertiary)
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
            content()
        }
    }
}

extension View {
    func homeCard(padding: EdgeInsets = EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NavigationStyle.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AppTheme.shared.colors.border, lineWidth: 1)
            }
    }
}
