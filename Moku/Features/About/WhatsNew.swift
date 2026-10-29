import SwiftUI

/// Desktop ChangelogModal: what changed, shown once after an update.
enum WhatsNew {
    struct Release: Identifiable {
        let version: String
        let notes: [String]
        var id: String { version }
    }

    /// Newest first. Add an entry with each release.
    static let releases = [
        Release(version: "0.1.0", notes: [
            "Sync your library, folders and reading progress with Moku on your computer (Settings → Sync).",
            "Novel reader with paper, sepia and dark themes and adjustable type.",
            "Mark chapters read or unread, select several at once, and download ranges from a title.",
            "Search by genre, load more results, and pin your favourite sources.",
            "Picture in Picture, background audio, AirPlay and skip intro for anime.",
            "Background library updates with new-chapter notifications.",
            "Track a title on AniList, or switch it to another source, from Manage.",
        ]),
    ]

    static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}

struct WhatsNewView: View {
    let release: WhatsNew.Release
    let done: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Version \(release.version)").font(.subheadline).foregroundStyle(GeneralStyle.label)
                    ForEach(release.notes, id: \.self) { note in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(NavigationStyle.accent).frame(width: 6, height: 6)
                            Text(note).font(.body).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(NavigationStyle.background.ignoresSafeArea())
            .foregroundStyle(GeneralStyle.text)
            .navigationTitle("What’s new")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Got it", action: done) } }
        }
        .presentationDetents([.medium, .large])
        .themedColorScheme()
    }
}
