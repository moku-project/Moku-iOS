import SwiftUI

enum GeneralStyle {
    static let border = Color(white: 37 / 255)
    static let faint = Color(white: 155 / 255)
    static let label = Color(red: 185 / 255, green: 188 / 255, blue: 192 / 255)
    static let text = Color(red: 232 / 255, green: 230 / 255, blue: 224 / 255)
    static var divider: some View { Rectangle().fill(border).frame(height: 1) }
}
struct GeneralSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 18, weight: .semibold))
                .foregroundStyle(GeneralStyle.text)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            content()
            GeneralStyle.divider
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct GeneralRow<Control: View>: View {
    @State private var availableWidth: CGFloat = 400
    let title: String
    let detail: String
    @ViewBuilder let control: () -> Control
    init(_ title: String, detail: String, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control
    }
    private var label: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 15)).foregroundStyle(GeneralStyle.label)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.system(size: 13)).foregroundStyle(GeneralStyle.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    var body: some View {
        Group {
            if availableWidth >= 300 {
                HStack(spacing: 16) {
                    label.frame(maxWidth: .infinity, alignment: .leading)
                    control().fixedSize(horizontal: true, vertical: false)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    label.frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Spacer(minLength: 0)
                        control()
                    }
                }
            }
        }.frame(minHeight: 44).padding(.vertical, 14)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                availableWidth = $0
            }
    }
}
struct GeneralToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule().fill(configuration.isOn ? NavigationStyle.accent : Color(white: 23 / 255))
                .overlay(
                    Capsule().strokeBorder(
                        configuration.isOn ? NavigationStyle.accent : Color(white: 62 / 255))
                )
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(configuration.isOn ? .white : GeneralStyle.faint)
                        .frame(width: 18, height: 18).padding(3)
                }.frame(width: 42, height: 24).frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
            }
    }
}
struct GeneralButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14)).foregroundStyle(GeneralStyle.text)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color(white: configuration.isPressed ? 23 / 255 : 13 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(GeneralStyle.border))
            .frame(minHeight: 44).contentShape(Rectangle())
    }
}
extension View {
    func generalInput() -> some View {
        self.font(.system(size: 14)).foregroundStyle(GeneralStyle.text)
            .padding(.vertical, 10).padding(.horizontal, 8)
            .background(Color(white: 13 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(GeneralStyle.border))
    }
}
