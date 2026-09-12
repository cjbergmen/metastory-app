import Foundation
import AVFoundation
import MediaPlayer
import UIKit

/// Background audio and the lock-screen transport.
///
/// The page keeps doing the actual playing — it owns the crossfade, the
/// prosody filter and the listening-time log, and reimplementing that natively
/// would be a rewrite with nothing to show for it. What the page *can't* do is
/// keep sound coming once iOS suspends the web view, or put controls on the
/// lock screen. So this module owns two things:
///
///   1. an active `.playback` audio session, which (with the `audio`
///      background mode in Info.plist) is what lets WebKit's media elements
///      keep running with the screen off; and
///   2. `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`, wired straight
///      back into the page's own transport functions.
final class AudioModule: NSObject, BridgeModule {

    static let shared = AudioModule()

    weak var host: WebViewController?

    private var isSessionActive = false
    private var hasRegisteredCommands = false
    private var nowPlaying: [String: Any] = [:]

    private override init() { super.init() }

    // MARK: - Session

    /// Declares the category at launch. Declaring is not activating: it does
    /// not duck or stop whatever the phone is already playing.
    static func configureSession() {
        do {
            // A2DP is the stereo music profile. Deliberately *not*
            // .allowBluetooth: that is the hands-free (HFP) profile meant for
            // calls, and offering it lets iOS route the album to a mono,
            // call-quality channel on some headsets.
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.allowAirPlay, .allowBluetoothA2DP]
            )
        } catch {
            NSLog("[Metastory] Could not set the audio category: \(error.localizedDescription)")
        }
    }

    private func activateSession() throws {
        guard !isSessionActive else { return }
        try AVAudioSession.sharedInstance().setActive(true)
        isSessionActive = true
        observeInterruptions()
        registerRemoteCommands()
    }

    private func deactivateSession() {
        guard isSessionActive else { return }
        // Letting other apps know means music that was ducked for us comes
        // back up on its own.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isSessionActive = false
    }

    // MARK: - BridgeModule

    func handle(action: String, payload: [String: Any], reply: Reply) {
        switch action {
        case "activateSession":
            do {
                try activateSession()
                reply.success(true)
            } catch {
                reply.failure(error)
            }

        case "deactivateSession":
            clearNowPlaying()
            deactivateSession()
            reply.success(true)

        case "setNowPlaying":
            setNowPlaying(payload)
            reply.success(true)

        case "setPlaybackState":
            setPlaybackState(payload)
            reply.success(true)

        case "clearNowPlaying":
            clearNowPlaying()
            reply.success(true)

        default:
            reply.failure("Unknown audio action '\(action)'.")
        }
    }

    // MARK: - Now Playing

    private func setNowPlaying(_ info: [String: Any]) {
        // Anything showing on the lock screen means we're playing, so make
        // sure the session is live even if the page forgot to ask.
        try? activateSession()

        var entry: [String: Any] = [
            MPMediaItemPropertyTitle: info["title"] as? String ?? "Safe Inside",
            MPMediaItemPropertyArtist: info["artist"] as? String ?? "Ventrality",
            MPMediaItemPropertyAlbumTitle: info["album"] as? String ?? "Safe Inside",
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]

        if let duration = (info["duration"] as? NSNumber)?.doubleValue, duration > 0 {
            entry[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let position = (info["position"] as? NSNumber)?.doubleValue {
            entry[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        }
        if let index = (info["index"] as? NSNumber)?.intValue {
            entry[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index
        }
        if let count = (info["count"] as? NSNumber)?.intValue {
            entry[MPNowPlayingInfoPropertyPlaybackQueueCount] = count
        }
        entry[MPNowPlayingInfoPropertyPlaybackRate] = (info["playing"] as? Bool ?? true) ? 1.0 : 0.0

        if let artwork = Self.artwork {
            entry[MPMediaItemPropertyArtwork] = artwork
        }

        nowPlaying = entry
        MPNowPlayingInfoCenter.default().nowPlayingInfo = entry
        registerRemoteCommands()
    }

    private func setPlaybackState(_ info: [String: Any]) {
        guard !nowPlaying.isEmpty else { return }

        let playing = info["playing"] as? Bool ?? false
        nowPlaying[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0

        if let position = (info["position"] as? NSNumber)?.doubleValue {
            nowPlaying[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        }
        if let duration = (info["duration"] as? NSNumber)?.doubleValue, duration > 0 {
            nowPlaying[MPMediaItemPropertyPlaybackDuration] = duration
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }

    private func clearNowPlaying() {
        nowPlaying = [:]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    /// The app icon stands in for cover art — the album ships as ten tracks
    /// with no per-track images.
    private static let artwork: MPMediaItemArtwork? = {
        guard
            let url = Bundle.main.url(forResource: "album-artwork", withExtension: "png"),
            let image = UIImage(contentsOfFile: url.path)
        else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }()

    // MARK: - Remote commands

    private func registerRemoteCommands() {
        guard !hasRegisteredCommands else { return }
        hasRegisteredCommands = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in self?.send("play") ?? .commandFailed }
        center.pauseCommand.addTarget { [weak self] _ in self?.send("pause") ?? .commandFailed }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.send("toggle") ?? .commandFailed }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.send("next") ?? .commandFailed }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.send("previous") ?? .commandFailed }
        center.stopCommand.addTarget { [weak self] _ in self?.send("stop") ?? .commandFailed }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard
                let self,
                let event = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            return self.send("seek", position: event.positionTime)
        }

        // Scrubbing forward and back a fixed amount doesn't suit ambient
        // tracks; leaving these off keeps the lock screen to play/pause/skip.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
    }

    @discardableResult
    private func send(_ command: String, position: Double? = nil) -> MPRemoteCommandHandlerStatus {
        guard let host else { return .commandFailed }
        let positionJSON = position.map { String($0) } ?? "null"
        host.emit(
            event: "remote-command",
            payload: "{\"command\":\(command.jsQuoted),\"position\":\(positionJSON)}"
        )
        return .success
    }

    // MARK: - Interruptions

    private func observeInterruptions() {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )

        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    /// A phone call, a timer, Siri. The page needs to know so its own
    /// play/pause state doesn't drift out of sync with what you can hear.
    @objc private func handleInterruption(_ notification: Notification) {
        guard
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }

        switch type {
        case .began:
            host?.emit(event: "remote-command", payload: "{\"command\":\"pause\",\"position\":null}")
        case .ended:
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            if options.contains(.shouldResume) {
                try? activateSession()
                host?.emit(event: "remote-command", payload: "{\"command\":\"play\",\"position\":null}")
            }
        @unknown default:
            break
        }
    }

    /// Headphones pulled out. The convention every music app follows is to
    /// pause rather than start playing out loud.
    @objc private func handleRouteChange(_ notification: Notification) {
        guard
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
        else { return }

        host?.emit(event: "remote-command", payload: "{\"command\":\"pause\",\"position\":null}")
    }
}
