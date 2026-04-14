import SwiftUI
import AppKit

/// An NSView-backed bridge that forwards trackpad scroll (two-finger swipe)
/// and magnify (pinch) events to SwiftUI callbacks.
///
/// - `onSwipePage`: called with -1 (swipe right → previous page) or +1 (swipe
///   left → next page) once per gesture, debounced so a single swipe doesn't
///   flip multiple pages.
/// - `onPinch`: called with the cumulative magnification at gesture end.
///   Positive = pinch-out (expand), negative = pinch-in (collapse).
struct TrackpadGestureView: NSViewRepresentable {
    var onSwipePage: (Int) -> Void
    var onPinch: (CGFloat) -> Void

    func makeNSView(context: Context) -> GestureCaptureView {
        let v = GestureCaptureView()
        v.onSwipePage = onSwipePage
        v.onPinch = onPinch
        return v
    }

    func updateNSView(_ nsView: GestureCaptureView, context: Context) {
        nsView.onSwipePage = onSwipePage
        nsView.onPinch = onPinch
    }
}

final class GestureCaptureView: NSView {
    var onSwipePage: ((Int) -> Void)?
    var onPinch: ((CGFloat) -> Void)?

    // Accumulated horizontal delta within a single continuous scroll gesture.
    private var scrollAccumX: CGFloat = 0
    private var scrollAccumY: CGFloat = 0
    private var pageFlipLocked = false

    // Accumulated magnification within a single pinch gesture.
    private var pinchAccum: CGFloat = 0

    // Threshold (points of trackpad delta) that counts as a full page swipe.
    private let pageSwipeThreshold: CGFloat = 60

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Never intercept clicks — we only want to *observe* scroll/magnify.
        return nil
    }

    override func scrollWheel(with event: NSEvent) {
        // Only react to trackpad scrolls (hasPreciseScrollingDeltas), not mouse wheels.
        guard event.hasPreciseScrollingDeltas else {
            super.scrollWheel(with: event)
            return
        }

        switch event.phase {
        case .began:
            scrollAccumX = 0
            scrollAccumY = 0
            pageFlipLocked = false
        case .changed:
            scrollAccumX += event.scrollingDeltaX
            scrollAccumY += event.scrollingDeltaY
            if !pageFlipLocked, abs(scrollAccumX) > abs(scrollAccumY) * 1.2 {
                if scrollAccumX <= -pageSwipeThreshold {
                    onSwipePage?(+1)   // swipe left → next page
                    pageFlipLocked = true
                } else if scrollAccumX >= pageSwipeThreshold {
                    onSwipePage?(-1)   // swipe right → previous page
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

    override func magnify(with event: NSEvent) {
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
