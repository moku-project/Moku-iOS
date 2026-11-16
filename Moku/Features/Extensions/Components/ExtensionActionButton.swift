import SwiftUI

/// App Store-style capsule: Install and Update are filled, Open is tinted; a ring while working, a check when done.
struct ExtensionActionButton: View {
    enum Kind { case install, update, open }

    let kind: Kind
    let busy: Bool
    let action: () -> Void
    @State private var justFinished = false
    @ScaledMetric(relativeTo: .subheadline) private var width = 76
    @ScaledMetric(relativeTo: .subheadline) private var height = 30

    private var title: String {
        switch kind {
        case .install: "Install"
        case .update: "Update"
        case .open: "Open"
        }
    }

    private var filled: Bool { kind != .open }

    var body: some View {
        Button(action: action) {
            ZStack {
                if busy {
                    ProgressView().controlSize(.small).tint(NavigationStyle.accent)
                } else if justFinished {
                    Image(systemName: "checkmark").font(.subheadline.weight(.bold))
                        .foregroundStyle(NavigationStyle.accent)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text(title).font(.subheadline.weight(.bold))
                        .foregroundStyle(
                            filled ? NavigationStyle.background : NavigationStyle.accent
                        )
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .frame(width: busy || justFinished ? height : width, height: height)
            .background {
                Capsule().fill(
                    busy || justFinished || !filled
                        ? NavigationStyle.accent.opacity(0.16) : NavigationStyle.accent)
            }
            .contentShape(Capsule())
            .animation(.snappy(duration: 0.25), value: busy)
            .animation(.snappy(duration: 0.25), value: justFinished)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .onChange(of: busy) { wasBusy, isBusy in
            guard wasBusy, !isBusy else { return }
            justFinished = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                justFinished = false
            }
        }
    }
}
