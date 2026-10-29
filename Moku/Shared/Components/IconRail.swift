import SwiftUI

extension EnvironmentValues {
    @Entry fileprivate var iconRailLabelsVisible = false
    @Entry fileprivate var iconRailVisibleRows = -1
    @Entry fileprivate var iconRailPresented = false
    @Entry fileprivate var iconRailItemCount = 1
    @Entry fileprivate var iconRailCoordinateSpace: UUID? = nil
    @Entry fileprivate var iconRailReduceMotion = false
}

struct PillDropdownOpenKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    func pillBackdrop(_ active: Bool) -> some View {
        self.blur(radius: active ? 4 : 0)
            .opacity(active ? 0.15 : 1)
    }
}

enum IconRailMotion {
    static let stepDuration = 0.09
    static func stagger(for rows: Int) -> Double {
        // Preserve the previous total: rows × 70 ms + 160 ms.
        // Redistribute 70 ms from movement to the gaps between steps.
        0.07 + 0.07 / Double(max(1, rows))
    }
}

/// A shared view picker with an icon rail and labels outside its surface.
struct IconRail<Content: View>: View {
    let title: String
    let symbol: String
    let isPresented: Bool
    let itemCount: Int
    let reduceMotion: Bool
    var labelFont: Font = .subheadline.weight(.medium)
    var iconSize: CGFloat = 22
    var iconColor: Color = .white
    var instantTitleChange = false
    var iconOnly = false
    var trailing = false
    var controlIdentifier = ""
    var controlLabel: String? = nil
    let toggle: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var coordinateSpace = UUID()
    @State private var visibleRows = -1
    @ScaledMetric private var chevronWidth: CGFloat = 10
    private var expanded: Bool { visibleRows >= 0 }
    private let iconOnlyChevronSpacing: CGFloat = -4
    private var trailingRailInset: CGFloat {
        iconOnly && trailing ? iconOnlyChevronSpacing + chevronWidth : 0
    }

    private var selectedTitle: some View {
        Group {
            if instantTitleChange {
                Text(title).font(labelFont).lineLimit(1)
                    .id(title).transition(.identity).contentTransition(.identity)
            } else {
                Text(title).font(labelFont).lineLimit(1)
            }
        }
        .transaction { transaction in
            if instantTitleChange {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var dropdownChevron: some View {
        PhosphorIcon("CaretDown").iconSize(10)
            .foregroundStyle(.secondary)
            .opacity(isPresented || expanded ? 0 : 1)
            .transaction { $0.animation = nil }
            .accessibilityHidden(true)
    }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: iconOnly ? iconOnlyChevronSpacing : (expanded ? 12 : -4)) {
                PhosphorIcon(symbol).iconSize(iconSize)
                    .foregroundStyle(iconColor)
                    .frame(width: 44, height: 44)
                if !iconOnly {
                    HStack(spacing: 6) {
                        selectedTitle
                        dropdownChevron
                    }
                    .padding(.trailing, 14)
                }
                if iconOnly { dropdownChevron }
            }
            .animation(
                reduceMotion || !expanded ? nil : .easeOut(duration: IconRailMotion.stepDuration),
                value: expanded
            )
            .foregroundStyle(.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(controlIdentifier)
        .accessibilityLabel(controlLabel ?? title)
        .accessibilityValue(title)
        .overlay(alignment: trailing ? .trailing : .leading) {
            if iconOnly {
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .padding(trailing ? .trailing : .leading, 56 + trailingRailInset)
                    .offset(x: reduceMotion || expanded ? 0 : (trailing ? 36 : -36))
                    .opacity(expanded ? 1 : 0)
                    .animation(
                        reduceMotion || !expanded
                            ? nil : .easeOut(duration: IconRailMotion.stepDuration),
                        value: expanded
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background(alignment: trailing ? .topTrailing : .topLeading) {
            Capsule()
                .fill(NavigationStyle.surface)
                .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
                .frame(
                    width: 44,
                    height: 44 + CGFloat(max(0, visibleRows)) * 44 + (visibleRows > 0 ? 4 : 0)
                )
                .opacity(expanded ? 1 : 0)
                .padding(.trailing, trailingRailInset)
                .allowsHitTesting(false)
        }
        .overlay(alignment: trailing ? .topTrailing : .topLeading) {
            // Closed menus have no rows to lay out or geometry observers to run.
            // Keep rows mounted until the closing animation has finished.
            if isPresented || expanded {
                VStack(alignment: trailing ? .trailing : .leading, spacing: 0, content: content)
                    .coordinateSpace(name: coordinateSpace)
                    .environment(\.iconRailCoordinateSpace, coordinateSpace)
                    .environment(\.iconRailVisibleRows, visibleRows)
                    .environment(\.iconRailPresented, isPresented)
                    .environment(\.iconRailItemCount, itemCount)
                    .environment(\.iconRailReduceMotion, reduceMotion)
                    .padding(.bottom, 4)
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(height: CGFloat(itemCount) * 44 + 4, alignment: .top)
                    .mask(alignment: .top) {
                        Rectangle().frame(
                            height: CGFloat(max(0, visibleRows)) * 44 + (visibleRows > 0 ? 4 : 0))
                    }
                    .offset(y: 44)
                    .padding(.trailing, trailingRailInset)
                    .allowsHitTesting(isPresented)
                    .accessibilityHidden(!isPresented)
            }
        }
        .task(id: "\(isPresented)-\(reduceMotion)-\(itemCount)") {
            let target = isPresented ? itemCount : -1
            if reduceMotion {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { visibleRows = target }
                return
            }
            // Each step reveals the next row and extends its rail. Reversing
            // direction retracts the lowest visible row first, even mid-animation.
            while visibleRows != target {
                guard !Task.isCancelled else { return }
                let next = visibleRows + (visibleRows < target ? 1 : -1)
                withAnimation(
                    .easeOut(duration: itemCount == 0 ? 0.16 : IconRailMotion.stepDuration)
                ) {
                    visibleRows = next
                }
                if visibleRows != target {
                    do {
                        try await Task.sleep(for: .seconds(IconRailMotion.stagger(for: itemCount)))
                    } catch {
                        return
                    }
                }
            }
        }
        .preference(key: PillDropdownOpenKey.self, value: isPresented)
    }
}

struct IconRailRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    var iconOnRight = false
    let action: () -> Void
    @Environment(\.iconRailPresented) private var presented
    @Environment(\.iconRailItemCount) private var itemCount
    @Environment(\.iconRailCoordinateSpace) private var coordinateSpace
    @State private var rowIndex = 1
    @Environment(\.iconRailReduceMotion) private var reduceMotion

    @Environment(\.iconRailVisibleRows) private var visibleRows
    private var revealed: Bool { visibleRows >= rowIndex }

    var body: some View {
        let space = coordinateSpace
        return Button(action: action) {
            HStack(spacing: 12) {
                if iconOnRight { rowLabel }
                rowIcon
                if !iconOnRight { rowLabel }

            }
            .contentShape(Rectangle())
            .opacity(revealed ? 1 : 0)
            .offset(y: reduceMotion || revealed ? 0 : -4)
            .animation(
                reduceMotion ? nil : .easeOut(duration: IconRailMotion.stepDuration),
                value: revealed)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .allowsHitTesting(presented && revealed)
        .accessibilityHidden(!presented || !revealed)
        .onGeometryChange(for: Int.self) { geometry in
            guard let coordinateSpace = space else { return 1 }
            return max(
                1, Int((geometry.frame(in: .named(coordinateSpace)).minY / 44).rounded()) + 1)
        } action: {
            rowIndex = $0
        }

    }
    private var rowIcon: some View {
        PhosphorIcon(symbol).iconSize(22)
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.55))
            .frame(width: 36, height: 36)
            .background {
                if selected {
                    Circle().fill(NavigationStyle.accent.opacity(0.16))
                }
            }
            .frame(width: 44, height: 44)

    }

    private var rowLabel: some View {
        Text(title).font(.system(size: 17, weight: selected ? .medium : .regular))
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.55))
            .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
            .padding(iconOnRight ? .leading : .trailing, 8)
            .offset(
                x: reduceMotion || revealed
                    ? 0 : (iconOnRight ? 1 : -1) * CGFloat(36 + 10 * max(0, rowIndex - 1)))

    }

}
