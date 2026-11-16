import SwiftUI

/// A settings category page: a native grouped Form over the app background.
struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        Form(content: content)
            .scrollContentBackground(.hidden)
            .background(NavigationStyle.background.ignoresSafeArea())
            .accessibilityIdentifier("settings.scroll")
    }
}

/// A row title with an optional explanatory second line.
struct SettingsLabel: View {
    let title: String
    var detail: String = ""
    init(_ title: String, detail: String = "") {
        self.title = title
        self.detail = detail
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if !detail.isEmpty {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct SettingsToggle: View {
    let title: String
    var detail: String = ""
    @Binding var isOn: Bool
    init(_ title: String, detail: String = "", isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }
    var body: some View {
        Toggle(isOn: $isOn) { SettingsLabel(title, detail: detail) }
            .accessibilityIdentifier(title)
    }
}

/// A menu picker row. Pass `identifier` to keep an existing accessibility identifier.
struct SettingsPicker<Value: Hashable>: View {
    let title: String
    var detail: String = ""
    @Binding var selection: Value
    let options: [(Value, String)]
    var identifier: String?
    init(
        _ title: String, detail: String = "", selection: Binding<Value>,
        options: [(Value, String)], identifier: String? = nil
    ) {
        self.title = title
        self.detail = detail
        _selection = selection
        self.options = options
        self.identifier = identifier
    }
    var body: some View {
        Picker(selection: $selection) {
            ForEach(options.indices, id: \.self) { index in
                Text(options[index].1).tag(options[index].0)
            }
        } label: {
            SettingsLabel(title, detail: detail)
        }
        .accessibilityIdentifier(identifier ?? "settings.picker.\(title)")
    }
}

/// A tappable row that leads somewhere else (a pushed page or a sheet).
struct SettingsLinkRow: View {
    let title: String
    var detail: String = ""
    var systemImage: String?
    let action: () -> Void
    init(
        _ title: String, detail: String = "", systemImage: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(NavigationStyle.accent)
                        .frame(width: 28)
                }
                SettingsLabel(title, detail: detail)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
    }
}

/// Status or error text at the end of a settings page.
struct SettingsNotice: View {
    let text: String?
    var retry: (() -> Void)?
    var body: some View {
        if let text {
            Section {
                Text(text).font(.footnote).foregroundStyle(.secondary)
                if let retry { Button("Retry", action: retry) }
            }
        }
    }
}
