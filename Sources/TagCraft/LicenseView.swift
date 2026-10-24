import SwiftUI
import AppKit

struct LicenseTermsView: View {
    @State private var showFullLicense = false
    let required: Bool
    let accept: () -> Void
    let close: () -> Void
    let decline: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("License & Usage Notice").font(.title2.bold())
            Text("Free, open-source software under AGPL-3.0, version 3 only. Review proposed changes and keep backups of important files. This notice adds no licensing restrictions.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(showFullLicense ? "Show Usage Notice" : "Read Full AGPL-3.0 License") { showFullLicense.toggle() }
            ScrollView {
                Text(showFullLicense ? LicenseTerms.licenseText : LicenseTerms.text).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Text("Notice version " + LicenseTerms.version + " · Supplement " + LicenseTerms.supplementVersion).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if required {
                    Button("Quit", action: decline)
                    Button("Continue", action: accept).buttonStyle(.borderedProminent)
                } else { Button("Done", action: close).keyboardShortcut(.cancelAction) }
            }
        }.padding(24).frame(minWidth: 780, idealWidth: 780, maxWidth: .infinity, minHeight: 480, idealHeight: 650, maxHeight: .infinity).background(ResizableReviewSheet())
            .interactiveDismissDisabled(required)
    }
}
struct LicenseGateRoot: View {
    @EnvironmentObject var m: Model
    var settings = false
    @State private var showRequired = false
    @State private var quitAfterDismissal = false
    var body: some View {
        Group {
            if m.noticeAcknowledged {
                if settings { LibraryStructureView() } else { ContentView() }
            } else {
                VStack(spacing: 18) {
                    Text("TagCraft Music Librarian").font(.title2.bold())
                    Text("Review License & Usage Notice to continue.")
                    Button("Review Notice") { showRequired = true }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if !m.noticeAcknowledged { showRequired = true } }
        .onChange(of: m.noticeAcknowledged) { _, accepted in if accepted { showRequired = false } }
        .sheet(isPresented: Binding(get: { showRequired }, set: { value in
            if value || m.noticeAcknowledged || quitAfterDismissal { showRequired = value }
        }), onDismiss: {
            if quitAfterDismissal {
                DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            } else if !m.noticeAcknowledged { showRequired = true }
        }) {
            LicenseTermsView(required: true, accept: {
                LicenseAcceptance.acknowledge(defaults: AppPreferences.defaults, release: AppRelease.noticeRelease)
                m.noticeAcknowledged = true; showRequired = false
            }, close: {}, decline: {
                quitAfterDismissal = true; showRequired = false
            })
        }
    }
}
