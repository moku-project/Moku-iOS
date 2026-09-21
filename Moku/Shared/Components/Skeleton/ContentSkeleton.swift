import SwiftUI

/// Content-shaped placeholders. Motion is decorative; assistive technology gets
/// one status element rather than fake titles, buttons, or repeating announcements.
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var radius: CGFloat = 5
    var body: some View {
        RoundedRectangle(cornerRadius: radius).fill(.primary.opacity(0.09))
            .frame(width: width, height: height)
    }
}

private struct SkeletonMotion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("preferences.animations") private var animations = true
    @State private var pulse = false
    let label: String
    private var animate: Bool { !reduceMotion && animations && scenePhase == .active }
    func body(content: Content) -> some View {
        content
            .opacity(animate && pulse ? 0.45 : 1)
            .animation(
                animate
                    ? .easeInOut(duration: SkeletonTiming.halfCycle).repeatForever(
                        autoreverses: true) : nil, value: pulse
            )
            .task(id: animate) {
                pulse = false
                if animate {
                    await Task.yield()
                    pulse = true
                }
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}

extension View {
    func skeletonMotion(_ label: String = "Content is being prepared") -> some View {
        modifier(SkeletonMotion(label: label))
    }
}

struct ContentSkeleton: View {
    enum Style {
        case extensions, results, chapters, settings, library, home, startup, reader, player, chips,
            cover
    }
    let style: Style
    var count = 4
    var body: some View {
        Group {
            switch style {
            case .cover:
                Rectangle().fill(.primary.opacity(0.08))
            case .extensions: rows(imageWidth: 64, imageHeight: 64)
            case .results: rows(imageWidth: 88, imageHeight: 126)
            case .chapters: rows(imageWidth: 0, imageHeight: 52)
            case .settings: rows(imageWidth: 0, imageHeight: 58)
            case .chips:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 8) {
                    ForEach(0..<6) { _ in SkeletonBlock(height: 44, radius: 10) }
                }
            case .library:
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(0..<count, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 10) {
                            Rectangle().fill(.primary.opacity(0.08)).aspectRatio(
                                2 / 3, contentMode: .fit
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            SkeletonBlock(height: 16)
                            SkeletonBlock(width: 80, height: 12)
                        }
                    }
                }
            case .home:
                VStack(alignment: .leading, spacing: 24) {
                    SkeletonBlock(height: 230, radius: 16)
                    SkeletonBlock(width: 120, height: 20)
                    rows(imageWidth: 42, imageHeight: 60)
                }
            case .startup:
                VStack(spacing: 24) {
                    SkeletonBlock(width: 100, height: 22).padding(.top, 16)
                    HStack { ForEach(0..<4) { _ in SkeletonBlock(height: 22) } }
                    rows(imageWidth: 64, imageHeight: 80)
                    Spacer(minLength: 20)
                    SkeletonBlock(height: 56, radius: 28)
                }.padding(20)
            case .reader:
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.07))
                        .frame(
                            width: min(geometry.size.width, geometry.size.height * 0.7),
                            height: geometry.size.height
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .player:
                VStack(spacing: 14) {
                    Rectangle().fill(.white.opacity(0.08)).aspectRatio(16 / 9, contentMode: .fit)
                    HStack {
                        SkeletonBlock(width: 120, height: 12)
                        Spacer()
                        SkeletonBlock(width: 40, height: 12)
                    }
                }.padding(20).frame(maxWidth: 800)
            }
        }.skeletonMotion()
    }
    private func rows(imageWidth: CGFloat, imageHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(0..<count, id: \.self) { index in
                HStack(spacing: 12) {
                    if imageWidth > 0 {
                        SkeletonBlock(width: imageWidth, height: imageHeight, radius: 6)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        GeometryReader { geometry in
                            SkeletonBlock(
                                width: geometry.size.width * (index.isMultiple(of: 2) ? 0.8 : 0.6),
                                height: 17)
                        }.frame(height: 17)
                        SkeletonBlock(width: 110, height: 12)
                        if imageHeight > 60 { SkeletonBlock(width: 65, height: 10) }
                    }.frame(maxWidth: .infinity)
                    if style == .extensions { SkeletonBlock(width: 22, height: 6, radius: 3) }
                }.frame(minHeight: imageHeight)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
