import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ArtworkOptions: View {
    @EnvironmentObject var m: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("New image size", selection: $m.artworkMaxEdge) {
                Text("Original dimensions").tag(0)
                Text("Maximum 1600 px").tag(1600)
                Text("Maximum 1000 px").tag(1000)
                Text("Maximum 600 px").tag(600)
            }
            Toggle("Replace all embedded pictures", isOn: $m.replaceAllArtwork)
            Text("Size applies when choosing or dropping the next image.").foregroundStyle(.secondary)
        }.font(.caption)
    }
}
@MainActor extension Model {
    func resizeFrontArtwork() {
        guard !busy, let track = selected.first, selection.count == 1, artworkMaxEdge > 0,
              let cover = pictures.first(where: { $0.type == 3 }) else { return }
        do {
            let stamp = FileJobs.fingerprint(track.url)
            let current = try ID3(Data(contentsOf: track.url, options: .mappedIfSafe))
            guard EmbeddedPicture.read(current).first(where: { $0.type == 3 })?.data == cover.data else { throw TagError(message: "Artwork changed since this view was opened. Reopen Artwork & Details before resizing.") }
            let data = try ArtworkImage.prepare(cover.data, maxEdge: artworkMaxEdge)
            guard data != cover.data else { message = "Front cover already fits the selected size."; return }
            showTechnical = false
            runPlans([.init(source: track.url, destination: track.url, artwork: data, expectedSize: stamp.0, expectedDate: stamp.1)], label: "Resize Front Cover")
        } catch { message = error.localizedDescription }
    }
    func exportArtwork(_ picture: EmbeddedPicture) {
        let panel = NSSavePanel()
        let type = UTType(mimeType: picture.mime) ?? .data
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = "TagCraft Artwork." + (type.preferredFilenameExtension ?? "bin")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try picture.data.write(to: url, options: .atomic) } catch { message = error.localizedDescription }
    }
    func acceptArtworkDrop(_ providers: [NSItemProvider], batch: Bool) -> Bool {
        guard let provider = providers.first, !busy else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                do {
                    guard ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()) else { throw TagError(message: "Drop a JPEG or PNG image.") }
                    let data = try ArtworkImage.prepare(Data(contentsOf: url), maxEdge: self.artworkMaxEdge)
                    if batch { self.batchArtworkData = data; self.batchApplyArtwork = true; self.batchRemoveArtwork = false }
                    else if let track = self.selected.first, self.selection.count == 1, !self.busy {
                        let stamp = FileJobs.fingerprint(track.url)
                        self.showTechnical = false
                        self.runPlans([.init(source: track.url, destination: track.url, artwork: data, replaceAllArtwork: self.replaceAllArtwork, expectedSize: stamp.0, expectedDate: stamp.1)], label: "Set Front Cover")
                    }
                } catch { self.message = error.localizedDescription }
            }
        }
        return true
    }
}
