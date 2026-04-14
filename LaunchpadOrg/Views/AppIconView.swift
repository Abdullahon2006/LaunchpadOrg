import SwiftUI
import AppKit

struct AppIconView: View {
    @Environment(LayoutStore.self) private var store
    let item: AppItem
    var iconSize: CGFloat = 88
    @Binding var selectedAppID: UUID?
    /// When non-nil, the context menu shows a "Remove from Folder" item.
    var onRemoveFromFolder: (() -> Void)? = nil

    private var isSelected: Bool { selectedAppID == item.id }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: iconSize * 0.22, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.18 : 0))
                    .overlay(
                        RoundedRectangle(cornerRadius: iconSize * 0.22, style: .continuous)
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
                .font(.system(size: max(10, min(13, iconSize * 0.14)), weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: iconSize + 28)
        }
        .contentShape(Rectangle())
        // Double-click launches; single click selects.
        .onTapGesture(count: 2) { AppLauncher.launch(item) }
        .onTapGesture(count: 1) { selectedAppID = item.id }
        .contextMenu {
            Button("Open") { AppLauncher.launch(item) }
            Button("Show in Finder") { AppLauncher.showInFinder(item) }
            if let onRemoveFromFolder {
                Divider()
                Button("Remove from Folder", role: .destructive) { onRemoveFromFolder() }
            }
        }
        .help(item.name)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}
