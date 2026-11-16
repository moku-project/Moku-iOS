import SwiftUI

/// Uses the shared anchored dropdown rather than a system popover.
struct ChoicePicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]

    private var selectedLabel: String { options.first { $0.0 == selection }?.1 ?? "" }

    var body: some View {
        OverflowMenu {
            ForEach(options, id: \.0) { option in
                Button {
                    selection = option.0
                } label: {
                    Text(option.1)
                        .foregroundStyle(
                            selection == option.0 ? NavigationStyle.accent : Color.primary)
                }
                .accessibilityAddTraits(selection == option.0 ? .isSelected : [])
            }
        } label: {
            HStack(spacing: 8) {
                if !title.isEmpty {
                    Text(title).foregroundStyle(.primary)
                    Spacer(minLength: 12)
                }
                Text(selectedLabel)
                    .foregroundStyle(NavigationStyle.accent)
                    .lineLimit(1)
                PhosphorIcon("CaretDown", size: 10).foregroundStyle(.secondary)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(title.isEmpty ? selectedLabel : title)
        .accessibilityValue(selectedLabel)
    }
}
