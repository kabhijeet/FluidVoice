import Foundation
#if arch(arm64)
import MediaRemoteAdapter
#endif

/// Thread-safe guard that ensures a CheckedContinuation is resumed at most once.
///
/// MediaRemoteAdapter's `getTrackInfo` callback can fire multiple times under certain
/// race conditions (e.g., rapid media state changes, system under load). Since
/// `CheckedContinuation` must be resumed exactly once, a duplicate `resume` call
/// triggers a fatal `SIGTRAP` (EXC_BREAKPOINT) crash.
///
/// This guard serializes access via `NSLock` and silently drops duplicate resumes.
private final class ContinuationOnceGuard<T: Sendable>: @unchecked Sendable {
    private var resumed = false
    private let lock = NSLock()

    /// Attempts to resume the continuation. Returns `true` if this was the first call
    /// (continuation was actually resumed), `false` if a prior call already resumed it.
    @discardableResult
    func resume(_ continuation: CheckedContinuation<T, Never>, returning value: T) -> Bool {
        lock.lock()
        let alreadyResumed = resumed
        if !alreadyResumed { resumed = true }
        lock.unlock()

        if alreadyResumed {
            DebugLogger.shared.warning(
                "ContinuationOnceGuard: Suppressed duplicate resume (MediaRemoteAdapter callback fired more than once)",
                source: "MediaPlaybackService"
            )
            return false
        }
        continuation.resume(returning: value)
        return true
    }
}

/// Service that wraps MediaRemoteAdapter's MediaController to provide
/// controlled pause/resume functionality during transcription.
///
/// This service ensures we only pause media if it's currently playing,
/// and only resume if we were the ones who paused it.
@MainActor
final class MediaPlaybackService {
    static let shared = MediaPlaybackService()

    #if arch(arm64)
    private let mediaController = MediaController()
    #endif

    private init() {}

    // MARK: - Public API

    #if arch(arm64)
    /// Pauses system media playback if something is currently playing.
    ///
    /// - Returns: `true` if we successfully paused playback, `false` if nothing was playing
    ///   or if we couldn't determine playback state.
    ///
    /// - Note: Uses `ContinuationOnceGuard` to protect against `MediaRemoteAdapter`
    ///   firing the `getTrackInfo` callback more than once, which would otherwise
    ///   crash with `EXC_BREAKPOINT` (SIGTRAP) due to double-resume of a
    ///   `CheckedContinuation`.
    func pauseIfPlaying() async -> Bool {
        return await withCheckedContinuation { continuation in
            // Guard against MediaRemoteAdapter firing the callback multiple times.
            // A double-resume of CheckedContinuation is a fatal error (SIGTRAP).
            let once = ContinuationOnceGuard<Bool>()

            self.mediaController.getTrackInfo { [weak self] trackInfo in
                guard let self = self else {
                    once.resume(continuation, returning: false)
                    return
                }

                // If no track info is available, nothing is playing
                guard let trackInfo = trackInfo else {
                    DebugLogger.shared.debug(
                        "MediaPlaybackService: No track info available, nothing to pause",
                        source: "MediaPlaybackService"
                    )
                    once.resume(continuation, returning: false)
                    return
                }

                // Determine if media is currently playing
                // Use isPlaying if available, otherwise check playbackRate
                let isPlaying: Bool
                if let playing = trackInfo.payload.isPlaying {
                    isPlaying = playing
                } else {
                    // playbackRate of 1.0 typically means playing, 0.0 means paused
                    isPlaying = (trackInfo.payload.playbackRate ?? 0.0) > 0.0
                }

                // Log what we found
                DebugLogger.shared.debug(
                    """
                    MediaPlaybackService: Track info received
                    - App: \(trackInfo.payload.applicationName ?? "Unknown")
                    - Bundle: \(trackInfo.payload.bundleIdentifier ?? "Unknown")
                    - Title: \(trackInfo.payload.title ?? "Unknown")
                    - isPlaying: \(trackInfo.payload.isPlaying?.description ?? "nil")
                    - playbackRate: \(trackInfo.payload.playbackRate?.description ?? "nil")
                    - Determined playing: \(isPlaying)
                    """,
                    source: "MediaPlaybackService"
                )

                if isPlaying {
                    DebugLogger.shared.info(
                        "MediaPlaybackService: Media is playing, sending pause command",
                        source: "MediaPlaybackService"
                    )
                    self.mediaController.pause()
                    once.resume(continuation, returning: true)
                } else {
                    DebugLogger.shared.debug(
                        "MediaPlaybackService: Media is not playing, no action needed",
                        source: "MediaPlaybackService"
                    )
                    once.resume(continuation, returning: false)
                }
            }
        }
    }

    /// Resumes media playback only if we were the ones who paused it.
    ///
    /// - Parameter wePaused: `true` if `pauseIfPlaying()` returned `true` for this session.
    func resumeIfWePaused(_ wePaused: Bool) async {
        guard wePaused else {
            DebugLogger.shared.debug(
                "MediaPlaybackService: We didn't pause media, not resuming",
                source: "MediaPlaybackService"
            )
            return
        }

        DebugLogger.shared.info(
            "MediaPlaybackService: Resuming media playback (we paused it)",
            source: "MediaPlaybackService"
        )

        // Use explicit play() command - never toggle
        self.mediaController.play()
    }
    #else
    // Intel Mac stub - media control not available
    func pauseIfPlaying() async -> Bool {
        DebugLogger.shared.debug(
            "MediaPlaybackService: Not available on Intel Macs",
            source: "MediaPlaybackService"
        )
        return false
    }

    func resumeIfWePaused(_ wePaused: Bool) async {
        // No-op on Intel
    }
    #endif
}
