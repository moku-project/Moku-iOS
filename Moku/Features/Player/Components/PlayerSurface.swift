import AVFoundation
import SwiftUI

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.layerPlayer.videoGravity = .resizeAspect
        view.layerPlayer.player = player
        return view
    }
    func updateUIView(_ view: Surface, context: Context) { view.layerPlayer.player = player }
    static func dismantleUIView(_ view: Surface, coordinator: ()) { view.layerPlayer.player = nil }
    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var layerPlayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
