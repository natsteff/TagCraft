import SwiftUI

struct UpdateCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var release: GitHubUpdateRelease?
    @State private var checking = true
    @State private var failure = ""
    @State private var task: Task<Void, Never>?
    private var installed: UpdateVersion? {
        let suffix = AppRelease.channel.lowercased() == "alpha" ? "-alpha" : AppRelease.channel.lowercased() == "beta" ? "-beta" : ""
        return UpdateVersion(AppRelease.version + suffix, build: Int(AppRelease.build) ?? 0)
    }
    private var newer: Bool { guard let local = installed, let remote = release?.version else { return false }; return remote > local }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Check for Updates").font(.title2.bold())
            Text("Installed: " + AppRelease.shortLabel + " (Build " + AppRelease.build + ")").foregroundStyle(.secondary)
            if checking {
                HStack { ProgressView().controlSize(.small); Text("Checking GitHub Releases…") }
            } else if !failure.isEmpty {
                Text("Couldn’t check for updates").font(.headline)
                Text(failure).foregroundStyle(.secondary)
            } else if let release {
                Text(newer ? "A newer version is available" : release.build == 0 ? "No newer version number found" : "You’re up to date").font(.headline)
                Text("Latest release: " + (release.name ?? release.tag_name) + (release.build > 0 ? " (Build \(release.build))" : ""))
                if newer {
                    Text("Download the disk image, quit TagCraft, and replace the app in Applications. Installation is manual.").foregroundStyle(.secondary)
                    if release.download(architecture: UpdateChecker.architecture) == nil {
                        Text("No matching \(UpdateChecker.architecture) DMG was found. Check the release page for available downloads.").foregroundStyle(.orange)
                    }
                }
                if release.build == 0 {
                    Text("This release does not declare a build number. Open its notes to check for same-version rebuilds.").font(.caption).foregroundStyle(.secondary)
                }
                Link("View Release Notes", destination: release.html_url)
            }
            Text("Checks run only when requested. Alpha and beta installations include prereleases; stable installations check stable releases. No music information is sent.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Link("All Releases", destination: UpdateChecker.releasesURL)
                Spacer()
                if newer, let url = release?.download(architecture: UpdateChecker.architecture) { Link("Download Update", destination: url).buttonStyle(.borderedProminent) }
                Button("Check Again") { start() }.disabled(checking)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 600)
            .onAppear { start() }
            .onDisappear { task?.cancel() }
    }
    private func start() {
        task?.cancel(); checking = true; failure = ""; release = nil
        task = Task { @MainActor in
            do {
                let result = try await UpdateChecker.check(includePrereleases: AppRelease.channel.lowercased() != "stable")
                guard !Task.isCancelled else { return }
                guard installed != nil else { failure = "The installed version could not be read. Open Releases to check manually."; checking = false; return }
                release = result
            } catch {
                guard !Task.isCancelled else { return }
                failure = error.localizedDescription
            }
            checking = false
        }
    }
}
