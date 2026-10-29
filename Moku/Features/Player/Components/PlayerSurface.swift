import AVFoundation
import AVKit
import Observation
import SwiftUI

/// Picture in Picture for the player layer. Starts automatically when the app
/// goes home while a video plays, or from the player's PiP button.
@MainActor @Observable final class PictureInPicture: NSObject, AVPictureInPictureControllerDelegate {
    private(set) var isActive = false
    private(set) var isPossible = false
    @ObservationIgnored fileprivate var controller: AVPictureInPictureController?
    @ObservationIgnored private var possibleObservation: NSKeyValueObservation?
    /// Called when the user taps "restore" in the PiP window.
    @ObservationIgnored var onRestore: (() -> Void)?

    static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    fileprivate func attach(_ layer: AVPlayerLayer) {
        guard Self.isSupported, controller == nil, let controller = AVPictureInPictureController(playerLayer: layer)
        else { return }
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = self
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            let possible = controller.isPictureInPicturePossible
            Task { @MainActor in self?.isPossible = possible }
        }
        self.controller = controller
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive { controller.stopPictureInPicture() } else { controller.startPictureInPicture() }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.isActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.isActive = false }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        // The player stays presented underneath PiP, so it is already restored.
        completionHandler(true)
        Task { @MainActor in self.onRestore?() }
    }
}

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    var qualityScaling = false
    /// In the background without PiP, iOS pauses a player that drives a layer;
    /// detaching it keeps the audio playing.
    var detached = false
    var pictureInPicture: PictureInPicture?

    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.layerPlayer.videoGravity = .resizeAspect
        view.layerPlayer.player = player
        pictureInPicture?.attach(view.layerPlayer)
        return view
    }
    func updateUIView(_ view: Surface, context: Context) {
        let target: AVPlayer? = detached ? nil : player
        if view.layerPlayer.player !== target { view.layerPlayer.player = target }
        view.layerPlayer.magnificationFilter = qualityScaling ? .trilinear : .linear
        view.layerPlayer.minificationFilter = qualityScaling ? .trilinear : .linear
    }
    static func dismantleUIView(_ view: Surface, coordinator: ()) { view.layerPlayer.player = nil }
    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var layerPlayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// The system AirPlay / audio route picker.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        view.tintColor = UIColor(white: 0.86, alpha: 1)
        view.activeTintColor = UIColor(red: 122 / 255, green: 170 / 255, blue: 122 / 255, alpha: 1)
        view.accessibilityLabel = "AirPlay"
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
