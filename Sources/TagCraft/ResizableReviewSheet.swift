import SwiftUI
import AppKit

/// Allow review dialogs to use more space without fixing their content to one size.
struct ResizableReviewSheet: NSViewRepresentable {
    final class Anchor: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window, window.sheetParent != nil else { return }
                window.styleMask.insert(.resizable)
                window.contentMinSize = NSSize(width: 640, height: 480)
            }
        }
    }
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {}
}
