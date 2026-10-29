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
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(spacing: 10) {
                    Image("MokuMark")
                        .resizable().scaledToFit().frame(width: 56, height: 56)
                        .foregroundStyle(NavigationStyle.accent)
                        .accessibilityHidden(true)
                    Text("Moku").font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(version).font(.subheadline).foregroundStyle(GeneralStyle.faint)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("about.version")
                    Text("A fast, minimal manga, novel and anime app. Sources run on your device; no server needed.")
                        .font(.subheadline).foregroundStyle(GeneralStyle.label)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)

                GeneralSection("Project") {
                    link("GitHub", detail: "moku-project/Moku-iOS",
                        url: "https://github.com/moku-project/Moku-iOS")
                    Button { reportOpen = true } label: {
                        GeneralRow("Report an issue", detail: "Bug or feature request, with the settings you choose") {
                            PhosphorIcon("CaretRight", size: 12).foregroundStyle(GeneralStyle.faint)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $reportOpen) { BugReportSheet() }
                    link("Website", detail: "moku-project.github.io",
                        url: "https://moku-project.github.io/")
                    link("Discord", detail: "Join the community",
                        url: "https://discord.gg/x97hj8zR72")
                }

                GeneralSection("Open source") {
                    GeneralRow("Moku for iOS", detail: "Apache License 2.0") { EmptyView() }
                    ForEach(Self.notices) { notice in
                        GeneralRow(notice.name, detail: notice.license) { EmptyView() }
                    }
                }

                Text("Moku does not host or distribute any content. Sources are added by you, and the developers have no affiliation with any content providers accessible through them.")
                    .font(.footnote).foregroundStyle(GeneralStyle.faint)
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .tracksNavigationScroll()
        .navigationTitle("About")
        .accessibilityIdentifier("about.page")
    }

    private func link(_ title: String, detail: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            GeneralRow(title, detail: detail) {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(GeneralStyle.faint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens in your browser")
    }
}

#if DEBUG
    #Preview {
        AboutView().preferredColorScheme(.dark)
    }
#endif
