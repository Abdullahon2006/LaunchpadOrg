import Foundation
import Observation

/// Shared drag state so the drop handler can read the source synchronously
/// instead of awaiting an `NSItemProvider.loadItem` callback (which made
/// drops feel laggy — often 50–100 ms per drop).
///
/// `.onDrag` still has to return an `NSItemProvider` (SwiftUI requires it
/// to start the drag session), but we ignore its payload on the receiving
/// end and just consult `DragState.source` directly.
@Observable
final class DragState {
    /// The node currently being dragged — (pageIndex, nodeIndex). `nil`
    /// means no drag in progress.
    var source: IndexPath?

    /// The node the pointer is currently hovering over mid-drag. Used by
    /// `AppIconView` / `FolderIconView` to render a target highlight.
    var hoverTarget: IndexPath?

    /// Page the pointer is over (used to auto-advance pages on hover at
    /// the left/right edge of the window mid-drag — future work).
    var hoverPage: Int?

    func clear() {
        source = nil
        hoverTarget = nil
        hoverPage = nil
    }
}
