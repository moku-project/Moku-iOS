import SwiftUI

struct ExtensionRow: View {
    let item: SourceExtension
    let search: (SourceExtension) -> Void
    let configure: (SourceExtension) -> Void
    let change: (ExtensionAction, SourceExtension) -> Void
    @ScaledMetric(relativeTo: .body) private var rowIconSize = 22
    var body: some View {
        HStack(spacing: 12) {
            Button {
                if item.installed && item.enabled { search(item) }
            } label: {
                ExtensionIdentity(item: item).frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!item.installed || !item.enabled)
                .accessibilityIdentifier("extensions.search.\(item.packageName)")
            OverflowMenu {
                if item.installed {
                    Button("Configure") { configure(item) }
                    if item.enabled { Button("Search source") { search(item) } }
                    if item.needsUpdate == true {
                        Button("Update") { change(.updateExtension, item) }
                    }
                } else {
                    Button("Install") { change(.installExtension, item) }
                        .accessibilityIdentifier("extensions.install.\(item.packageName)")
                }
            } label: {
                PhosphorIcon("DotsThree").iconSize(rowIconSize)
                    .foregroundStyle(.secondary).frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }

            .accessibilityLabel("Manage \(item.displayName)")
        }.padding(.vertical, 4)

    }
}
