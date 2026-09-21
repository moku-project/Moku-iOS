import SwiftUI
import UIKit

/// UIScrollView owns pan/pinch and a bounded window of decoded page images.
struct ReaderCanvas: UIViewRepresentable {
    let model: ReaderViewModel
    var active: Bool
    var reduceMotion: Bool
    let toggleChrome: () -> Void

    func makeCoordinator() -> CanvasCoordinator { CanvasCoordinator(self) }
    func makeUIView(context: Context) -> CanvasScrollView {
        let scroll = CanvasScrollView()
        context.coordinator.attach(scroll)
        return scroll
    }
    func updateUIView(_ scroll: CanvasScrollView, context: Context) {
        context.coordinator.update(self)
    }
    static func dismantleUIView(_ scroll: CanvasScrollView, coordinator: CanvasCoordinator) {
        coordinator.stop()
    }

}
