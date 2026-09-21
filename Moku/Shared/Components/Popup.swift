import SwiftUI

struct Popup<Content: View, Actions: View>: View {
    let title: String
    let close: () -> Void
    var preferredHeight: CGFloat = 480
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea().onTapGesture(perform: close)
                VStack(spacing: 16) {
                    HStack {
                        Text(title).font(.headline)
                        Spacer()
                        Button(action: close) { PhosphorIcon("X").frame(width: 44, height: 44) }
                            .accessibilityLabel("Close popup")
                    }
                    ScrollView { content().frame(maxWidth: .infinity, alignment: .leading) }
                        .scrollBounceBehavior(.basedOnSize)
                    HStack(spacing: 16, content: actions).frame(
                        maxWidth: .infinity, alignment: .trailing)
                }
                .padding(20).frame(maxWidth: 480)
                .frame(maxHeight: min(preferredHeight, max(200, geometry.size.height - 32)))
                .modifier(FloatingSurface(cornerRadius: 24)).padding(16)
            }
        }.buttonStyle(.plain).tint(NavigationStyle.accent)
            .accessibilityAddTraits(.isModal)
    }
}
