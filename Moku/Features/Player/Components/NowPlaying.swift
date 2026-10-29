import MediaPlayer
import UIKit

/// Lock screen, Control Center and headphone controls for the anime player.
@MainActor final class NowPlaying {
    private var targets: [(MPRemoteCommand, Any)] = []
    private var lastKey = ""

    func attach(
        toggle: @escaping @MainActor () -> Void, seek: @escaping @MainActor (Double) -> Void,
        skip: @escaping @MainActor (Double) -> Void, episode: @escaping @MainActor (Int) -> Void
    ) {
        detach()
        let center = MPRemoteCommandCenter.shared()
        func add(_ command: MPRemoteCommand, _ handler: @escaping @MainActor (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
            command.isEnabled = true
            let target = command.addTarget { event in
                MainActor.assumeIsolated { handler(event) }
            }
            targets.append((command, target))
        }
        add(center.togglePlayPauseCommand) { _ in toggle(); return .success }
        add(center.playCommand) { _ in toggle(); return .success }
        add(center.pauseCommand) { _ in toggle(); return .success }
        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.preferredIntervals = [10]
        add(center.skipBackwardCommand) { _ in skip(-10); return .success }
        add(center.skipForwardCommand) { _ in skip(10); return .success }
        add(center.nextTrackCommand) { _ in episode(1); return .success }
        add(center.previousTrackCommand) { _ in episode(-1); return .success }
        add(center.changePlaybackPositionCommand) { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            seek(event.positionTime)
            return .success
        }
    }

    /// The system extrapolates elapsed time from the rate, so this only needs
    /// to run when something other than the clock changes.
    func update(title: String, episode: String, position: Double, duration: Double, rate: Float, playing: Bool) {
        let key = "\(title)|\(episode)|\(Int(duration))|\(playing)|\(rate)|\(Int(position / 5))"
        guard key != lastKey else { return }
        lastKey = key
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: episode,
            MPMediaItemPropertyAlbumTitle: title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? Double(rate) : 0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
    }

    func detach() {
        for (command, target) in targets { command.removeTarget(target) }
        targets.removeAll()
        lastKey = ""
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
