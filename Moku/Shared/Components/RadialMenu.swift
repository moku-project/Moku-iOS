import SwiftUI

enum RadialMenuLevel: String {
    case closed, root, add
    var isSubmenu: Bool { self == .add }
    var symbol: String {
        switch self {
        case .closed: "List"
        case .root: "X"
        case .add: "Plus"
        }
    }
}

struct RadialAction: Identifiable {
    var id: String { title }
    let title: String
    let symbol: String
    var isEnabled = true
    let perform: () -> Void
}

struct RadialMenu: View {
    @Binding var level: RadialMenuLevel
    let reduceMotion: Bool
    let actions: [RadialAction]
    var accessibilityPrefix = "library"
    var toolsTitle = "Library"
    @State private var displayedActions: [RadialAction] = []
    @State private var revealed = false
    @State private var transitioning = false
    @State private var flyingSymbol: String?
    @State private var flyingOffset = CGSize.zero
    @State private var haptic = false

    var body: some View {
        // Every orbit is an overlay, so it cannot change the FAB's layout or hit frame.
        Button {
            haptic.toggle()
            level = level.isSubmenu ? .root : level == .closed ? .root : .closed
        } label: {
            PhosphorIcon(
                level.isSubmenu
                    ? (transitioning ? level.symbol : "CaretLeft") : level.symbol
            )
            .font(.system(size: 24, weight: .regular))
            .contentTransition(reduceMotion ? .identity : .opacity)
            .foregroundStyle(NavigationStyle.accent)
            .opacity(flyingSymbol == nil ? 1 : 0)
            .frame(width: 56, height: 56)
            .modifier(FloatingSurface(cornerRadius: 28))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            level.isSubmenu
                ? "Back to \(toolsTitle) tools"
                : level == .closed ? "\(toolsTitle) tools" : "Close \(toolsTitle.lowercased()) menu"
        )
        .accessibilityIdentifier("\(accessibilityPrefix).fab")
        .accessibilityAction(.escape) { level = level.isSubmenu ? .root : .closed }
        .overlay(alignment: .bottomTrailing) {
            ForEach(Array(displayedActions.enumerated()), id: \.element.id) { index, action in
                let offset = orbit(index, count: displayedActions.count)
                Button {
                    haptic.toggle()
                    if !reduceMotion && level == .root
                        && action.title == "Add"
                    {
                        flyingSymbol = action.symbol
                        flyingOffset = offset
                    }
                    action.perform()
                } label: {
                    VStack(spacing: 5) {
                        PhosphorIcon(action.symbol).iconSize(22)
                            .frame(width: 40, height: 40)
                            .background(NavigationStyle.surface, in: Circle())
                            .overlay {
                                Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                            }
                        Text(action.title).font(.caption).fixedSize()
                    }
                    .foregroundStyle(.primary)
                    .frame(width: displayedActions.count == 5 ? 56 : 90, height: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!action.isEnabled)
                .offset(
                    x: (revealed ? offset.width : 0) + (displayedActions.count == 5 ? 0 : 17),
                    y: (revealed ? offset.height : 0) - 2
                )
                .opacity(revealed ? (action.isEnabled ? 1 : 0.35) : 0)
                .scaleEffect(revealed ? 1 : 0.35)
                .allowsHitTesting(level != .closed && revealed && !transitioning)
                .accessibilityHidden(level == .closed || !revealed || transitioning)
                .accessibilityIdentifier("\(accessibilityPrefix).action.\(action.title)")
                .animation(
                    reduceMotion
                        ? nil
                        : .spring(response: 0.34, dampingFraction: 0.8), value: revealed)
            }
        }
        .overlay {
            if let flyingSymbol {
                PhosphorIcon(flyingSymbol).iconSize(24).foregroundStyle(NavigationStyle.accent)
                    .offset(flyingOffset)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .sensoryFeedback(.selection, trigger: haptic)
        .task(id: level) {
            let wasRevealed = revealed
            transitioning = true
            revealed = false
            if reduceMotion {
                flyingSymbol = nil
            } else if wasRevealed || flyingSymbol != nil {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                    flyingOffset = .zero
                }
                do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            flyingSymbol = nil
            displayedActions = actions
            if !reduceMotion && level != .closed {
                // Mount the actions at their collapsed positions before animating outward.
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard !Task.isCancelled else { return }
            }
            transitioning = false
            revealed = level != .closed
        }
    }

    private func orbit(_ index: Int, count: Int) -> CGSize {
        let radius: CGFloat = count == 5 ? 140 : count > 2 ? 135 : 84
        let angle = Double(index) / Double(max(1, count - 1)) * .pi / 2
        return CGSize(width: -CGFloat(sin(angle)) * radius, height: -CGFloat(cos(angle)) * radius)
    }
}
