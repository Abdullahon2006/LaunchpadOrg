import AppKit

/// Installs process-wide NSEvent monitors for trackpad scroll + magnify.
///
/// Using `NSEvent.addLocalMonitorForEvents` (rather than an NSView subclass
/// with `scrollWheel`/`magnify` overrides) guarantees we see every gesture
/// regardless of which view is under the cursor or whether SwiftUI decides
/// to hit-test through our overlay. This was the reason two-finger swipe
/// didn't register before.
final class GestureMonitor {
    static let shared = GestureMonitor()

    var onSwipePage: ((Int) -> Void)?
    var onPinch: ((CGFloat) -> Void)?

    private var scrollMonitor: Any?
    private var magnifyMonitor: Any?

    // Per-gesture accumulators.
    private var scrollAccumX: CGFloat = 0
    private var scrollAccumY: CGFloat = 0
    private var pageFlipLocked = false
    private var pinchAccum: CGFloat = 0

    private let pageSwipeThreshold: CGFloat = 55

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
        guard event.hasPreciseScrollingDeltas else { return }

        switch event.phase {
        case .began:
            scrollAccumX = 0
            scrollAccumY = 0
            pageFlipLocked = false
        case .changed:
            scrollAccumX += event.scrollingDeltaX
            scrollAccumY += event.scrollingDeltaY
            guard !pageFlipLocked else { return }
            if abs(scrollAccumX) > abs(scrollAccumY) * 1.2 {
                if scrollAccumX <= -pageSwipeThreshold {
                    onSwipePage?(+1)
                    pageFlipLocked = true
                } else if scrollAccumX >= pageSwipeThreshold {
                    onSwipePage?(-1)
                    pageFlipLocked = true
                }
            }
        case .ended, .cancelled:
            scrollAccumX = 0
            scrollAccumY = 0
            pageFlipLocked = false
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
