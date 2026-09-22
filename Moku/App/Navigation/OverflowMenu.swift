import SwiftUI

@MainActor @Observable final class OverflowMenuPresentation {
    var content: AnyView?
    var anchor = CGRect.zero
    var owner: UUID?

    func dismiss() {
        content = nil
        owner = nil
    }
}

/// Row menus render at the page root so lists cannot clip the dropdown.
struct OverflowMenu<Content: View, Label: View>: View {
    @Environment(OverflowMenuPresentation.self) private var presentation: OverflowMenuPresentation?
    @State private var anchor = CGRect.zero
    @State private var id = UUID()
    @ViewBuilder var content: () -> Content
    @ViewBuilder var label: () -> Label

    var body: some View {
        if let presentation {
            hostedMenu(presentation)
        } else {
            // Standalone screens and previews may not have a root popup host.
            SwiftUI.Menu {
                content()
            } label: {
                label()
            }
            .menuStyle(.borderlessButton)
        }
    }

    private func hostedMenu(_ presentation: OverflowMenuPresentation) -> some View {
        Button {
            if presentation.owner == id {
                presentation.dismiss()
            } else {
                presentation.anchor = anchor
                presentation.owner = id
                presentation.content = AnyView(content())
            }
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: { frame in
            anchor = frame
            // A scrolled-away or rotated anchor should never leave a detached menu behind.
            if presentation.owner == id && presentation.anchor != frame { presentation.dismiss() }
        }
        .onDisappear { if presentation.owner == id { presentation.dismiss() } }
    }
}

struct OverflowMenuHost: ViewModifier {
    @State private var presentation = OverflowMenuPresentation()

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(presentation.content == nil)
            .accessibilityHidden(presentation.content != nil)
            .overlay {
                if let menu = presentation.content {
                    OverflowMenuPanel(
                        menu: menu, anchor: presentation.anchor, dismiss: presentation.dismiss
                    )
                    .id(presentation.owner)
                }
            }
            .environment(presentation)
    }
}

private struct OverflowMenuPanel: View {
    let menu: AnyView
    let anchor: CGRect
    let dismiss: () -> Void
    @State private var measured = CGSize.zero

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) { menu }
            .buttonStyle(OverflowMenuActionStyle(dismiss: dismiss))
            .padding(4)
    }

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global).origin
            let width = min(measured.width, max(44, geometry.size.width - 24))
            let height = min(measured.height, max(44, geometry.size.height - 24))
            let x = max(12, min(anchor.maxX - origin.x - width, geometry.size.width - width - 12))
            let below = anchor.maxY - origin.y + 4
            let above = anchor.minY - origin.y - height - 4
            let y = max(
                12,
                min(
                    below + height <= geometry.size.height - 12 ? below : above,
                    geometry.size.height - height - 12))
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001).ignoresSafeArea().contentShape(Rectangle())
                    .onTapGesture(perform: dismiss).accessibilityHidden(true)
                rows.fixedSize().hidden().allowsHitTesting(false).accessibilityHidden(true)
                    .onGeometryChange(for: CGSize.self) {
                        $0.size
                    } action: {
                        measured = $0
                    }
                ScrollView {
                    rows.frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: width, height: height)
                .background(Color(white: 0.085), in: RoundedRectangle(cornerRadius: 16))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16).strokeBorder(
                        .white.opacity(0.12), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.4), radius: 14, y: 5)
                .opacity(measured == .zero ? 0 : 1)
                .offset(x: x, y: y)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("overflow.menu")
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape, dismiss)
            }
        }
    }
}

private struct OverflowMenuActionStyle: PrimitiveButtonStyle {
    let dismiss: () -> Void
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            dismiss()
            configuration.trigger()
        } label: {
            configuration.label
                .font(.body)
                .foregroundStyle(
                    configuration.role == .destructive ? Color.red : .white.opacity(0.92)
                )
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(OverflowMenuPressStyle())
    }
}

private struct OverflowMenuPressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? .white.opacity(0.08) : .clear,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .opacity(isEnabled ? 1 : 0.4)
    }
}
