import SwiftUI

/// A title with its latest session, as Home shows it.
struct HomeItem: Identifiable {
    let entry: HomeEntry
    let session: HomeSession
    var id: String { entry.id }

    var isAnime: Bool { entry.media == "Anime" }

    /// "Ch.12 · Page 37", or the unread count when the chapter list isn't known yet.
    var detail: String {
        if let chapter = entry.chapters.first(where: { $0.id == session.chapterID }) {
            return isAnime ? chapter.displayTitle : "\(chapter.displayTitle) · Page \(session.page)"
        }
        return entry.unreadCount > 0 ? "\(entry.unreadCount) unread" : "In progress"
    }
}

/// The most recent title, with a blurred cover backdrop and a Resume button.
struct HomeContinueCard: View {
    let item: HomeItem
    var opening = false
    let resume: () -> Void
    let details: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Button(action: details) {
                HomeCover(url: item.entry.coverURL, contentMode: .fill)
                    .frame(width: 98, height: 147)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(item.entry.title)")
            .accessibilityIdentifier("home.continue.details")
            VStack(alignment: .leading, spacing: 6) {
                Text(item.isAnime ? "Continue Watching" : "Continue Reading")
                    .font(.caption.weight(.semibold)).foregroundStyle(NavigationStyle.accent)
                Text(item.entry.title).font(.headline).lineLimit(2)
                Text(item.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                HomeSeriesProgress(entry: item.entry)
                Button(action: resume) {
                    Label("Resume", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .disabled(opening)
                .accessibilityIdentifier("home.continue.resume")
            }
            .frame(maxWidth: .infinity, minHeight: 147, alignment: .leading)
        }
        .padding(14)
        .background {
            ZStack {
                NavigationStyle.surface
                HomeCover(url: item.entry.coverURL, contentMode: .fill)
                    .blur(radius: 28).opacity(0.4)
                LinearGradient(
                    colors: [NavigationStyle.background.opacity(0.3), NavigationStyle.background.opacity(0.85)],
                    startPoint: .leading, endPoint: .trailing)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppTheme.shared.colors.border, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.continue")
    }
}

/// Shown before anything has been read: points to Browse and Extensions.
struct HomeWelcomeCard: View {
    let browse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "book.pages")
                    .font(.title3).foregroundStyle(NavigationStyle.accent)
                    .frame(width: 44, height: 44)
                    .background(NavigationStyle.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Start Your Library").font(.headline)
                    Text("Add a source, then pick something to read or watch.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Button(action: browse) {
                    Label("Browse", systemImage: "magnifyingglass").frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                NavigationLink(value: Route.more(.extensions)) {
                    Label("Extensions", systemImage: "puzzlepiece.extension").frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline.weight(.semibold))
        }
        .homeCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.welcome")
    }
}

/// A compact title row for Up Next and Recent.
struct HomeMediaRow: View {
    let item: HomeItem
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                HomeCover(url: item.entry.coverURL, contentMode: .fill)
                    .frame(width: 36, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.entry.title).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.entry.title), \(item.detail)")
    }
}
