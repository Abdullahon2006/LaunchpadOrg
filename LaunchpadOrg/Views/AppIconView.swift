import SwiftUI
import AppKit

struct AppIconView: View {
    @Environment(LayoutStore.self) private var store
    let item: AppItem
    var iconSize: CGFloat = 88
    @Binding var selectedAppID: UUID?

    private var isSelected: Bool { selectedAppID == item.id }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Selection highlight (rendered behind icon).
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.18 : 0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(isSelected ? 0.55 : 0), lineWidth: 1.5)
                    )
                    .frame(width: iconSize + 16, height: iconSize + 16)

                Image(nsImage: store.icon(for: item))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
            }

            Text(item.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: iconSize + 20)
        }
        .contentShape(Rectangle())
        // Double-click launches the app; single click only selects.
        // IMPORTANT: the count:2 handler must be registered *before* the
        // count:1 handler so SwiftUI waits for a potential second click.
        .onTapGesture(count: 2) { AppLauncher.launch(item) }
        .onTapGesture(count: 1) { selectedAppID = item.id }
        .contextMenu {
            Button("Open") { AppLauncher.launch(item) }
            Button("Show in Finder") { AppLauncher.showInFinder(item) }
        }
        .help(item.name)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}
