import SwiftUI

/// Presented above the navigation shell, so the backdrop blocks the whole app.
struct MokuLinksHost: ViewModifier {
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!isPresented)
            .accessibilityHidden(isPresented)
            .environment(\.openMokuLinks) { isPresented = true }
            .overlay {
                if isPresented {
                    MokuLinksModal { isPresented = false }
                }
            }
    }
}

struct MokuLinksModal: View {
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("preferences.animations") private var animations = true
    @State private var isVisible = false
    @State private var isClosing = false
    @AccessibilityFocusState private var titleFocused: Bool
    @ScaledMetric(relativeTo: .body) private var preferredHeight = 410
    @ScaledMetric(relativeTo: .title2) private var titleSize = 25
    @ScaledMetric(relativeTo: .body) private var rowSize = 16
    @ScaledMetric(relativeTo: .caption) private var detailSize = 12

    private var motion: Animation? {
        guard animations else { return nil }
        return reduceMotion
            ? .easeOut(duration: 0.18) : .spring(response: 0.38, dampingFraction: 0.86)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(isVisible ? 0.64 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismiss)
                    .accessibilityHidden(true)

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 10) {
                            Image("MokuMark")
                                .resizable().scaledToFit().frame(width: 64, height: 64)
                                .foregroundStyle(NavigationStyle.accent)
                                .accessibilityHidden(true)
                            Text("Moku")
                                .font(.system(size: titleSize, weight: .semibold))
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityFocused($titleFocused)

                        }
                        VStack(spacing: 8) {
                            destination(
                                "Discord", detail: "Join the community", asset: "DiscordBrand",
                                url: "https://discord.gg/x97hj8zR72", id: "discord")
                            destination(
                                "GitHub", detail: "moku-project / Moku-iOS", asset: "GitHubBrand",
                                url: "https://github.com/moku-project/Moku-iOS", id: "github")
                            destination(
                                "Website", detail: "Official Moku website", asset: nil,
                                url: "https://moku-project.github.io/", id: "website")
                        }

                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                }
                .scrollBounceBehavior(.basedOnSize)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
                .frame(maxHeight: min(preferredHeight, max(180, geometry.size.height - 40)))
                .background {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color(white: 0.055))

                }
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                }
                .overlay(alignment: .topTrailing) {
                    Button(action: dismiss) {
                        PhosphorIcon("X", size: 15)
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).padding(8)
                    .accessibilityLabel("Close Moku links")
                    .accessibilityIdentifier("moku.links.close")
                }
                .opacity(isVisible ? 1 : 0)
                .scaleEffect(isVisible || reduceMotion ? 1 : 0.94)
                .offset(y: isVisible || reduceMotion ? 0 : 18)
                .padding(.horizontal, 20)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
                .accessibilityIdentifier("moku.links.modal")
                .accessibilityAction(.escape, dismiss)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(motion) { isVisible = true }
            titleFocused = true
        }
    }

    private func destination(
        _ title: String, detail: String, asset: String?, url: String, id: String
    ) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 14) {
                Group {
                    if let asset {
                        Image(asset).renderingMode(.original).resizable().scaledToFit()
                    } else {
                        PhosphorIcon("Globe", size: 24)
                            .foregroundStyle(GeneralStyle.text)
                    }
                }
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: rowSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(detail).font(.system(size: detailSize))
                        .foregroundStyle(.white.opacity(0.5))
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(16).frame(minHeight: 64)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15).strokeBorder(
                    .white.opacity(0.06), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(MokuLinkPressStyle())
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityHint("Opens in your browser")
        .accessibilityIdentifier("moku.links.\(id)")
    }

    private func dismiss() {
        guard !isClosing else { return }
        isClosing = true
        withAnimation(motion, completionCriteria: .logicallyComplete) {
            isVisible = false
        } completion: {
            close()
        }
    }
}

private struct MokuLinkPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}
