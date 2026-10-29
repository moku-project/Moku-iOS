import SwiftUI
import UIKit

enum MenuStyle { static let cornerRadius: CGFloat = 10 }

/// Match the longest label, including row padding and panel inset.
func libraryMenuWidth(_ labels: [String]) -> CGFloat {
    let font = UIFont.systemFont(ofSize: 17, weight: .medium)
    return ceil(
        labels.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0)
        + 46
}

struct Dropdown<Content: View>: View {
    let title: String
    let maxHeight: CGFloat
    let preferredHeight: CGFloat
    var width: CGFloat = 236
    var showsTitle = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if showsTitle {
                    Text(title).font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 10)
                    Divider().padding(.horizontal, 2).padding(.bottom, 4)
                }
                content()
            }.padding(4)
        }
        .contentMargins(.all, 0, for: .scrollContent)
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: width, height: min(maxHeight, preferredHeight))
        .background(
            Color(red: 21 / 255, green: 21 / 255, blue: 21 / 255),
            in: RoundedRectangle(cornerRadius: MenuStyle.cornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MenuStyle.cornerRadius).strokeBorder(
                Color(white: 48 / 255), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: MenuStyle.cornerRadius))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) menu")
    }
}

struct MenuSection: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 6)
    }
}

struct MenuRow: View {
    let title: String
    var symbol: String?
    var selected = false
    var fontSize: CGFloat = 13
    var iconSize: CGFloat = 16
    var rowHeight: CGFloat = 44
    var centered = false
    var whiteText = false
    let action: () -> Void

    init(
        _ title: String, symbol: String? = nil, selected: Bool = false, fontSize: CGFloat = 13,
        iconSize: CGFloat = 16, rowHeight: CGFloat = 44, centered: Bool = false,
        whiteText: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.selected = selected
        self.fontSize = fontSize
        self.iconSize = iconSize
        self.rowHeight = rowHeight
        self.centered = centered
        self.whiteText = whiteText
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if centered { Spacer(minLength: 0) }
                if let symbol {
                    PhosphorIcon(symbol).iconSize(iconSize).frame(
                        width: iconSize + 2)
                }
                Text(title)
                    .fixedSize(horizontal: whiteText, vertical: false)
                Spacer(minLength: 0)
            }
            .font(.system(size: fontSize, weight: selected ? .medium : .regular))
            .foregroundStyle(
                whiteText ? .white : selected ? NavigationStyle.accent : Color(white: 0.72)
            )
            .padding(.horizontal, 10).frame(minHeight: rowHeight)
            .background(
                selected ? NavigationStyle.accent.opacity(0.14) : .clear,
                in: RoundedRectangle(cornerRadius: 3)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
