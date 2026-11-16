import SwiftUI
import UIKit

/// Version, project links, open-source notices and the content disclaimer.
struct AboutView: View {
    private struct Notice: Identifiable {
        let name: String
        let license: String
        var id: String { name }
    }

    private static let notices = [
        Notice(name: "Tsunagu", license: "Apache License 2.0"),
        Notice(name: "OpenJDK", license: "GPL v2 with Classpath Exception"),
        Notice(name: "FFmpeg", license: "LGPL v2.1"),
        Notice(name: "Go", license: "BSD 3-Clause"),
        Notice(name: "Phosphor Icons", license: "MIT License"),
    ]

    @State private var reportOpen = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image("MokuMark")
                        .resizable().scaledToFit().frame(width: 56, height: 56)
                        .foregroundStyle(NavigationStyle.accent)
                        .accessibilityHidden(true)
                    Text("Moku").font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(version).font(.subheadline).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("about.version")
                    Text(
                        "A fast, minimal manga, novel and anime app. Sources run on your device; no server needed."
                    )
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("Project") {
                link(
                    "GitHub", detail: "moku-project/Moku-iOS",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    url: "https://github.com/moku-project/Moku-iOS")
                Button {
                    reportOpen = true
                } label: {
                    Label("Report an Issue", systemImage: "ladybug")
                }
                link(
                    "Website", detail: "moku-project.github.io", systemImage: "globe",
                    url: "https://moku-project.github.io/")
                link(
                    "Discord", detail: "Join the community",
                    systemImage: "bubble.left.and.bubble.right",
                    url: "https://discord.gg/x97hj8zR72")
            }

            Section {
                LabeledContent("Moku for iOS", value: "Apache License 2.0")
                ForEach(Self.notices) { notice in
                    LabeledContent(notice.name, value: notice.license)
                }
            } header: {
                Text("Open Source")
            } footer: {
                Text(
                    "Moku does not host or distribute any content. Sources are added by you, and the developers have no affiliation with any content providers accessible through them."
                )
                .padding(.top, 8)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NavigationStyle.background.ignoresSafeArea())
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $reportOpen) { BugReportSheet() }
        .accessibilityIdentifier("about.page")
    }

    private func link(_ title: String, detail: String, systemImage: String, url: String)
        -> some View
    {
        Link(destination: URL(string: url)!) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).foregroundStyle(.primary)
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: systemImage)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityHint("Opens in your browser")
    }
}

#if DEBUG
    #Preview {
        AboutView().preferredColorScheme(.dark)
    }
#endif
