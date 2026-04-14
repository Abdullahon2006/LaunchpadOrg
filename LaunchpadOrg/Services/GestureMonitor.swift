import AppKit

/// Process-wide NSEvent monitor that forwards trackpad gestures to SwiftUI
/// via closures. A local monitor always sees events regardless of hit-test
/// plumbing — an NSView subclass with `scrollWheel`/`magnify` overrides
/// wouldn't, which is why the older implementation silently dropped
/// everything.
///
/// The page-swipe API is now *continuous*: ContentView gets per-frame
/// delta events and animates the pager offset directly, so the on-screen
/// motion tracks finger velocity. On gesture end we snap to the nearest
/// page based on the release position + velocity.
final class GestureMonitor {
    static let shared = GestureMonitor()

    // Continuous horizontal scroll delta (positive = finger right).
    var onScrollDelta: ((CGFloat) -> Void)?
    // Fired when the horizontal scroll gesture ends. The argument is the
    // total horizontal displacement accumulated during the gesture, which
    // the caller uses to decide whether to commit a page change.
    var onScrollEnd: ((CGFloat) -> Void)?
    // Pinch-in (negative) / pinch-out (positive) magnification at end.
    var onPinch: ((CGFloat) -> Void)?

    private var scrollMonitor: Any?
    private var magnifyMonitor: Any?

    private var accumX: CGFloat = 0
    private var accumY: CGFloat = 0
    private var horizontalLocked = false
    private var pinchAccum: CGFloat = 0

    // Raw delta in a scroll event that's too small is noise; ignore.
    private let noiseFloor: CGFloat = 0.1
    // Once horizontal movement exceeds this and dominates Y, we lock into
    // "page-swipe" mode for the rest of the gesture.
    private let lockThreshold: CGFloat = 6

    private init() {}

    func install() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            self?.handleMagnify(event)
            return event
        }
    }

    private func handleScroll(_ event: NSEvent) {
        // Trackpad only — mouse wheel has `hasPreciseScrollingDeltas == false`
        // and we don't want a ratchet wheel to jump pages.
        guard event.hasPreciseScrollingDeltas else { return }

        switch event.phase {
        case .began:
            accumX = 0
            accumY = 0
            horizontalLocked = false
        case .changed:
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            accumX += dx
            accumY += dy
            if !horizontalLocked,
               abs(accumX) > lockThreshold,
               abs(accumX) > abs(accumY) * 1.2 {
                horizontalLocked = true
            }
            if horizontalLocked, abs(dx) > noiseFloor {
                onScrollDelta?(dx)
            }
        case .ended, .cancelled:
            if horizontalLocked {
                onScrollEnd?(accumX)
            }
            accumX = 0
            accumY = 0
            horizontalLocked = false
        default:
            break
        }
    }

    private func handleMagnify(_ event: NSEvent) {
        switch event.phase {
        case .began:
            pinchAccum = 0
        case .changed:
            pinchAccum += event.magnification
        case .ended, .cancelled:
            if abs(pinchAccum) > 0.1 {
                onPinch?(pinchAccum)
            }
            pinchAccum = 0
        default:
            break
        }
    }
}
