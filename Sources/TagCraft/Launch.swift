import SwiftUI
import AppKit

@MainActor final class LaunchSplash {
    static let shared = LaunchSplash()
    private(set) var active = true
    private var panel: NSPanel?
    private var waitingWindows: [NSWindow] = []

    func present() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView:
            VStack(spacing: 18) {
                StatisticsBrandLogo(width: 320).frame(width: 320, height: 230)
                Text(AppRelease.fullLabel).font(.system(size: 12)).foregroundStyle(.secondary)
                ProgressView().controlSize(.small)
            }.frame(width: 420, height: 340)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                .preferredColorScheme(.light))
        panel.center()
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func register(_ window: NSWindow) {
        guard active else { return }
        if !waitingWindows.contains(where: { $0 === window }) { waitingWindows.append(window) }
        window.alphaValue = 0
        window.ignoresMouseEvents = true
    }

    func finishAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            active = false
            for window in waitingWindows {
                window.alphaValue = 1
                window.ignoresMouseEvents = false
            }
            waitingWindows.first?.makeKeyAndOrderFront(nil)
            waitingWindows.removeAll()
            panel?.orderOut(nil)
            panel?.close()
            panel = nil
        }
    }
}

@MainActor final class LaunchDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) { LaunchSplash.shared.present() }
    func applicationDidFinishLaunching(_ notification: Notification) { LaunchSplash.shared.finishAfterDelay() }
}

struct LaunchWindowGate: NSViewRepresentable {
    final class Anchor: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { LaunchSplash.shared.register(window) }
        }
    }
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {}
}
