import SwiftUI

struct HomeSectionHeading: View {
    let title: String
    var action: String? = nil
    var perform: () -> Void = {}
    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if let action {
                Button(action: perform) {
                    HStack(spacing: 5) {
                        Text(action)
                        PhosphorIcon("CaretRight")
                    }
                }
                .font(.caption).foregroundStyle(.secondary).frame(minHeight: 44)
            }
        }.frame(minHeight: 28)
    }
}

struct HomeEmptyRow: View {
    let text: String
    let symbol: String
    var body: some View {
        HStack(spacing: 12) {
            PhosphorIcon(symbol).foregroundStyle(.gray.opacity(0.5))
            Text(text).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }.padding(18).frame(minHeight: 76).homePanel()
    }
}
