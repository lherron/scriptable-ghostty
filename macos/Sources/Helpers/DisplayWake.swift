import CoreGraphics
import Foundation
import IOKit.pwr_mgt

/// Display-wake gate for surface creation.
///
/// libghostty's `ghostty_surface_new` needs an active WindowServer/Metal drawable.
/// When the main display is asleep (this happens on a locked/idle Mac whose system
/// sleep is otherwise prevented — e.g. a headless/Screen-Shared host), realize returns
/// no surface and the create fails 100% of the time. Caller-side retry/backoff does NOT
/// help: every attempt fails just as hard until something wakes the display.
///
/// This declares user activity (the documented "wake the display" API) and waits, bounded,
/// for the display to come back before we attempt to create a surface. See T-01799 for the
/// controlled repro (display asleep -> 15/15 fail; awake -> 0/N fail; lock-with-display-on
/// realizes fine, so the gate is display power, not the session lock).
enum DisplayWake {
    /// True when the main display has no active drawable (asleep / parked).
    static var mainDisplayAsleep: Bool {
        CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }

    /// If the main display is asleep, declare user activity to wake it and block (bounded)
    /// until it reports active, then settle briefly so the Metal device is ready before we
    /// realize a surface. No-op fast path when the display is already awake.
    ///
    /// Called on the main thread. We must SPIN THE RUN LOOP rather than block it: the
    /// display wake is processed via the app's main run loop, so `Thread.sleep`-ing here
    /// stalls the very wake we are waiting for (measured: a blocking wait never sees the
    /// display come active until the call returns and the loop is free again — it just
    /// burns the whole timeout). Spinning lets the wake land in-process so the subsequent
    /// surface create realizes. (T-01799.)
    ///
    /// We run the loop before creating any window, so there is no half-built surface to
    /// re-enter; a concurrent create that arrives during the spin simply queues.
    ///
    /// - Returns: whether the display is active by the time we return.
    @discardableResult
    static func wakeAndWait(timeout: TimeInterval = 8.0, settle: TimeInterval = 0.4) -> Bool {
        guard mainDisplayAsleep else { return true }

        var userActivityID: IOPMAssertionID = 0
        IOPMAssertionDeclareUserActivity(
            "ghostmux surface create" as CFString,
            kIOPMUserActiveLocal,
            &userActivityID)

        let deadline = Date().addingTimeInterval(timeout)
        while CGDisplayIsActive(CGMainDisplayID()) == 0, Date() < deadline {
            // Process run-loop sources for up to 100ms, then re-check.
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        let active = CGDisplayIsActive(CGMainDisplayID()) != 0
        // CGDisplayIsActive flips a beat before the Metal device is ready to back a new
        // surface; let the loop settle so the first post-wake create realizes instead of
        // losing the race.
        if active, settle > 0 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(settle))
        }
        return active
    }
}
