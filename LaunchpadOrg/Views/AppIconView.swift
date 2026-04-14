import SwiftUI
import AppKit

struct AppIconView: View {
    @Environment(LayoutStore.self) private var store
    let item: AppItem
    var iconSize: CGFloat = 88

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: store.icon(for: item))
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)

            Text(item.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: iconSize + 20)
        }
        .contentShape(Rectangle())
        .onTapGesture { AppLauncher.launch(item) }
        .contextMenu {
            Button("Open") { AppLauncher.launch(item) }
            Button("Show in Finder") { AppLauncher.showInFinder(item) }
        }
        .help(item.name)
    }
}
