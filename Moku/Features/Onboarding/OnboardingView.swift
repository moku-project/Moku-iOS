import SwiftUI

/// First-run walkthrough (desktop Onboarding + tour). Moku ships with no
/// sources, so the flow ends at the two ways to get content and at desktop sync.
struct OnboardingView: View {
    let openExtensions: () -> Void
    let openSettings: () -> Void
    let finish: () -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Page: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let body: String
    }

    private let pages = [
        Page(id: 0, symbol: "MokuMark", title: "Welcome to Moku",
             body: "Read manga and novels and watch anime from sources you choose. Sources run on this iPhone, with no account or server needed."),
        Page(id: 1, symbol: "PuzzlePiece", title: "Add your sources",
             body: "Moku doesn’t come with any content. Add a Mihon, Aniyomi or LNReader repository in Extensions, then install the sources you want. You can also import CBZ, EPUB and video files."),
        Page(id: 2, symbol: "ArrowsClockwise", title: "Bring your desktop library",
             body: "Use Moku on your computer? Turn on phone sync there, then connect in Settings → Sync to share your library, folders and reading progress."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { finish() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(GeneralStyle.label)
                    .frame(minWidth: 44, minHeight: 44)
                    .opacity(page < pages.count - 1 ? 1 : 0)
                    .accessibilityIdentifier("onboarding.skip")
            }
            .padding(.horizontal, 16)

            TabView(selection: $page) {
                ForEach(pages) { item in
                    content(item).tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(pages) { item in
                    Capsule()
                        .fill(item.id == page ? NavigationStyle.accent : GeneralStyle.border)
                        .frame(width: item.id == page ? 22 : 8, height: 8)
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.3), value: page)
            .accessibilityElement()
            .accessibilityLabel("Page \(page + 1) of \(pages.count)")
            .padding(.bottom, 24)

            actions
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NavigationStyle.background.ignoresSafeArea())
        .foregroundStyle(GeneralStyle.text)
        .accessibilityIdentifier("onboarding")
    }

    private func content(_ item: Page) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(NavigationStyle.accent.opacity(0.12)).frame(width: 132, height: 132)
                if item.symbol == "MokuMark" {
                    Image("MokuMark").resizable().scaledToFit().frame(width: 64, height: 64)
                        .foregroundStyle(NavigationStyle.accent)
                } else {
                    PhosphorIcon(item.symbol, size: 56).foregroundStyle(NavigationStyle.accent)
                }
            }
            .accessibilityHidden(true)
            Text(item.title).font(.title.weight(.semibold)).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(item.body).font(.body).foregroundStyle(GeneralStyle.label)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 10) {
            switch page {
            case 1:
                primary("Open Extensions") { finish(); openExtensions() }
                secondary("Not now") { withAnimation(reduceMotion ? nil : .easeInOut) { page += 1 } }
            case 2:
                primary("Get started") { finish() }
                secondary("Connect a desktop") { finish(); openSettings() }
            default:
                primary("Continue") { withAnimation(reduceMotion ? nil : .easeInOut) { page += 1 } }
                secondary(" ") {}.hidden()
            }
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline)
                .foregroundStyle(NavigationStyle.background)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(NavigationStyle.accent, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.primary")
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.medium))
                .foregroundStyle(NavigationStyle.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
    #Preview {
        OnboardingView(openExtensions: {}, openSettings: {}, finish: {})
            .preferredColorScheme(.dark)
    }
#endif
