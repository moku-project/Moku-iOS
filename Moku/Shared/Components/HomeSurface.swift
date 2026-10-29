import SwiftUI

struct CarouselBreadcrumbs: View {
    let count: Int
    let selection: Int
    let accessibilityPrefix: String
    let onSelect: (Int) -> Void

    var body: some View {
        if count > 1 {
            HStack(spacing: 0) {
                Button {
                    onSelect((selection + count - 1) % count)
                } label: {
                    PhosphorIcon("CaretLeft").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Previous slide")
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        Button {
                            onSelect(index)
                        } label: {
                            Capsule()
                                .fill(selection == index ? Color.white : Color.gray.opacity(0.4))
                                .frame(width: selection == index ? 22 : 6, height: 6)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Slide \(index + 1) of \(count)")
                        .accessibilityAddTraits(selection == index ? .isSelected : [])
                        .accessibilityIdentifier("\(accessibilityPrefix).breadcrumb.\(index)")
                    }
                }
                Spacer(minLength: 0)
                Text("\(selection + 1) / \(count)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Button {
                    onSelect((selection + 1) % count)
                } label: {
                    PhosphorIcon("CaretRight").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Next slide")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

extension View {
    func homePanel() -> some View {
        background(NavigationStyle.surface.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(
                    .white.opacity(0.08), lineWidth: 0.5)
            }
    }
}
