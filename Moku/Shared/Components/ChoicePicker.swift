import SwiftUI

/// A selection menu with highlighted rows and no system selection glyphs.
struct ChoicePicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]
    @State private var presented = false

    var body: some View {
        Button {
            presented.toggle()
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(options.first { $0.0 == selection }?.1 ?? "")
                    .foregroundStyle(NavigationStyle.accent)
                PhosphorIcon("CaretDown")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(options.first { $0.0 == selection }?.1 ?? "")
        .popover(isPresented: $presented) {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(options, id: \.0) { option in
                        MenuRow(option.1, selected: selection == option.0, fontSize: 16) {
                            selection = option.0
                            presented = false
                        }
                    }
                }.padding(8)
            }
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
            .frame(height: min(360, CGFloat(options.count) * 48 + 16))
            .presentationCompactAdaptation(.popover)
        }
    }
}
