import SwiftUI

/// Native asset-catalog rendering of the desktop's Phosphor artwork.
struct PhosphorIcon: View {
    let name: String
    let weight: String
    @ScaledMetric private var size: CGFloat

    init(_ name: String, size: CGFloat = 18, weight: String = "regular") {
        self.name = name.replacingOccurrences(of: ".fill", with: "")
        self.weight = name.hasSuffix(".fill") ? "fill" : weight
        _size = ScaledMetric(wrappedValue: size)
    }
    var body: some View {
        Image(name + "-" + weight).renderingMode(.template).resizable()
            .scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
    }
    func iconSize(_ value: CGFloat) -> PhosphorIcon {
        PhosphorIcon(name, size: value, weight: weight)
    }
}

extension Label where Title == Text, Icon == PhosphorIcon {
    @MainActor init(_ title: String, phosphor: String) {
        self.init {
            Text(title)
        } icon: {
            PhosphorIcon(phosphor)
        }
    }
}

extension Button where Label == SwiftUI.Label<Text, PhosphorIcon> {
    @MainActor init(
        _ title: String, phosphor: String, role: ButtonRole? = nil, action: @escaping () -> Void
    ) {
        self.init(role: role, action: action) { SwiftUI.Label(title, phosphor: phosphor) }
    }
}

extension Menu where Label == SwiftUI.Label<Text, PhosphorIcon> {
    @MainActor init(_ title: String, phosphor: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { SwiftUI.Label(title, phosphor: phosphor) }
    }
}

extension ContentUnavailableView
where Label == SwiftUI.Label<Text, PhosphorIcon>, Description == Text?, Actions == EmptyView {
    @MainActor init(_ title: String, phosphor: String, description: Text? = nil) {
        self.init {
            SwiftUI.Label(title, phosphor: phosphor)
        } description: {
            description
        }
    }
}
