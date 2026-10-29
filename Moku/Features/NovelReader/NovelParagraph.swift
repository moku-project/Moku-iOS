import SwiftUI
import UIKit

/// Justified paragraphs. SwiftUI `Text` has no justified alignment, so this
/// renders the same attributed run (bold and italic kept) through UIKit, with
/// light hyphenation so justified lines don't open wide gaps.
struct NovelParagraph: UIViewRepresentable {
    let text: AttributedString
    let font: NovelFont
    let size: CGFloat
    let lineSpacing: CGFloat
    let color: Color

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.isAccessibilityElement = true
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.attributedText = attributed()
        label.accessibilityLabel = String(text.characters)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        label.preferredMaxLayoutWidth = width
        let fitted = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
    }

    private func attributed() -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .justified
        style.lineSpacing = lineSpacing
        style.hyphenationFactor = 0.3
        let result = NSMutableAttributedString()
        let ink = UIColor(color)
        for run in text.runs {
            let intent = run.inlinePresentationIntent ?? []
            var traits: UIFontDescriptor.SymbolicTraits = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
            if intent.contains(.emphasized) { traits.insert(.traitItalic) }
            result.append(NSAttributedString(
                string: String(text[run.range].characters),
                attributes: [.font: Self.uiFont(font, size: size, traits: traits), .foregroundColor: ink, .paragraphStyle: style]))
        }
        return result
    }

    static func uiFont(_ font: NovelFont, size: CGFloat, traits: UIFontDescriptor.SymbolicTraits = []) -> UIFont {
        let base: UIFont
        switch font {
        case .serif, .rounded, .mono, .sans:
            let system = UIFont.systemFont(ofSize: size)
            let design: UIFontDescriptor.SystemDesign =
                font == .serif ? .serif : font == .rounded ? .rounded : font == .mono ? .monospaced : .default
            base = system.fontDescriptor.withDesign(design).map { UIFont(descriptor: $0, size: size) } ?? system
        case .georgia, .palatino, .avenir:
            base = UIFont(name: font.postScriptName, size: size) ?? .systemFont(ofSize: size)
        }
        guard !traits.isEmpty, let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}
