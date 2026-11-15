import SwiftUI

/// A section title in the style of Apple's media apps: bold title, optional trailing link.
struct HomeSectionHeading<Accessory: View>: View {
    let title: String
    var action: String? = nil
    var perform: () -> Void = {}
    /// Pushes this page instead of calling `perform`.
    var link: Route? = nil
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            accessory()
            if let action {
                Group {
                    if let link {
                        NavigationLink(value: link) { actionLabel(action) }
                    } else {
                        Button(action: perform) { actionLabel(action) }
                    }
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
            }
        }
        .frame(minHeight: 44)
    }

    private func actionLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: "chevron.right").imageScale(.small)
        }
    }
}

extension HomeSectionHeading where Accessory == EmptyView {
    init(title: String, action: String? = nil, perform: @escaping () -> Void = {}, link: Route? = nil) {
        self.init(title: title, action: action, perform: perform, link: link) { EmptyView() }
    }
}

struct HomeEmptyRow: View {
    let text: String
    let systemImage: String
    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}
