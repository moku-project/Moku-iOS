import SwiftUI

/// Tap an installed source to browse it; the trailing button installs or updates, the rest is in the context menu.
struct ExtensionRow: View {
    let item: SourceExtension
    var busy = false
    let search: (SourceExtension) -> Void
    let configure: (SourceExtension) -> Void
    var openLibrary: (SourceExtension) -> Void = { _ in }
    var verify: ((SourceExtension) -> Void)?
    var uninstall: (SourceExtension) -> Void = { _ in }
    let change: (ExtensionAction, SourceExtension) -> Void

    private var browsable: Bool { item.installed && item.enabled }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if browsable { search(item) }
            } label: {
                ExtensionIdentity(item: item)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(browsable)
            .accessibilityHint(browsable ? "Browses this source" : "")
            .accessibilityIdentifier("extensions.search.\(item.packageName)")
            if !item.installed {
                ExtensionActionButton(kind: .install, busy: busy) {
                    change(.installExtension, item)
                }
                .accessibilityLabel("Install \(item.displayName)")
                .accessibilityIdentifier("extensions.install.\(item.packageName)")
            } else if item.needsUpdate == true {
                ExtensionActionButton(kind: .update, busy: busy) { change(.updateExtension, item) }
                    .accessibilityLabel("Update \(item.displayName)")
            } else if browsable {
                ExtensionActionButton(kind: .open, busy: busy) { search(item) }
                    .accessibilityLabel("Open \(item.displayName)")
                    .accessibilityIdentifier("extensions.open.\(item.packageName)")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if item.installed {
                Button("Uninstall", role: .destructive) { uninstall(item) }
                if item.needsUpdate == true {
                    Button("Update") { change(.updateExtension, item) }.tint(NavigationStyle.accent)
                }
            } else {
                Button("Install") { change(.installExtension, item) }.tint(NavigationStyle.accent)
            }
        }
        .contextMenu {
            if item.installed {
                if item.enabled {
                    Button("Browse Source", systemImage: "magnifyingglass") { search(item) }
                }
                if item.needsUpdate == true {
                    Button("Update", systemImage: "arrow.down.circle") {
                        change(.updateExtension, item)
                    }
                }
                Button("Source Settings", systemImage: "slider.horizontal.3") { configure(item) }
                Button("Library and Migration", systemImage: "arrow.left.arrow.right") {
                    openLibrary(item)
                }
                if let verify {
                    Button("Verify in Browser…", systemImage: "checkmark.shield") { verify(item) }
                }
                Divider()
                Button("Uninstall", systemImage: "trash", role: .destructive) { uninstall(item) }
            } else {
                Button("Install", systemImage: "arrow.down.circle") {
                    change(.installExtension, item)
                }
            }
        }
    }
}
