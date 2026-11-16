import SwiftUI

/// The iOS Settings row icon: a white symbol on a small colored rounded square.
struct SettingsTile: View {
    let symbol: String
    let color: Color
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 29

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                color.gradient, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// A Settings row label with its tile.
struct SettingsRowLabel: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            SettingsTile(symbol: symbol, color: color)
        }
    }
}

extension SettingsCategory {
    var tile: (symbol: String, color: Color) {
        switch self {
        case .general: ("gearshape.fill", .gray)
        case .appearance: ("paintbrush.fill", .blue)
        case .reader: ("book.fill", .orange)
        case .player: ("play.rectangle.fill", .red)
        case .library: ("books.vertical.fill", .brown)
        case .folders: ("folder.fill", .cyan)
        case .content: ("checkmark.shield.fill", .green)
        case .automation: ("wand.and.stars", .purple)
        case .performance: ("speedometer", .gray)
        case .keybinds: ("keyboard.fill", .gray)
        case .sync: ("arrow.triangle.2.circlepath", .green)
        case .storage: ("internaldrive.fill", .gray)
        case .server: ("server.rack", .indigo)
        case .auth: ("lock.fill", .yellow)
        case .tracking: ("person.crop.circle.badge.checkmark", .pink)
        case .about: ("info", .gray)
        case .devTools: ("hammer.fill", .gray)
        }
    }
}

extension MoreDestination {
    var tile: (symbol: String, color: Color) {
        switch self {
        case .extensions: ("puzzlepiece.extension.fill", .indigo)
        case .tracking: ("chart.line.uptrend.xyaxis", .teal)
        case .recent: ("clock.fill", .blue)
        case .about: ("info", .gray)
        }
    }
}
