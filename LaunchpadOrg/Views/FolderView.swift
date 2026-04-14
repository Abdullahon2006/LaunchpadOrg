import SwiftUI
import AppKit

struct FolderIconView: View {
    @Environment(LayoutStore.self) private var store
    let folder: AppFolder
    let apps: [AppItem]
    var iconSize: CGFloat = 88
    /// When true, the folder tile shows a prominent ring to signal that a
    /// dragged app will be dropped inside.
    var isDropTarget: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(isDropTarget ? 0.32 : 0.2))
                    .frame(width: iconSize, height: iconSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(isDropTarget ? 0.9 : 0.3),
                                    lineWidth: isDropTarget ? 2 : 1)
                    )

                let mini = min(iconSize / 3.5, 22)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(mini), spacing: 4), count: 3), spacing: 4) {
                    ForEach(Array(apps.prefix(9).enumerated()), id: \.offset) { _, app in
                        Image(nsImage: store.icon(for: app))
                            .resizable()
                            .frame(width: mini, height: mini)
                    }
                }
                .frame(width: iconSize - 16, height: iconSize - 16)
            }
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
            .scaleEffect(isDropTarget ? 1.06 : 1)
            .animation(.easeOut(duration: 0.15), value: isDropTarget)

            Text(folder.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .lineLimit(1)
                .frame(width: iconSize + 20)
        }
        .contentShape(Rectangle())
    }
}

struct FolderDetailView: View {
    let folder: AppFolder
    let apps: [AppItem]
    @Binding var selectedAppID: UUID?
    /// When true, the name TextField grabs focus on appear — used right after
    /// a folder is created by dropping two apps together, so the user can
    /// type a name immediately.
    var autoFocusName: Bool
    var onRename: (String) -> Void
    var onClose: () -> Void

    @State private var editingName: String
    @FocusState private var nameFocused: Bool

    init(folder: AppFolder,
         apps: [AppItem],
         selectedAppID: Binding<UUID?>,
         autoFocusName: Bool = false,
         onRename: @escaping (String) -> Void,
         onClose: @escaping () -> Void) {
        self.folder = folder
        self.apps = apps
        self._selectedAppID = selectedAppID
        self.autoFocusName = autoFocusName
        self.onRename = onRename
        self.onClose = onClose
        _editingName = State(initialValue: folder.name)
    }

    var body: some View {
        VStack(spacing: 24) {
            TextField("Folder name", text: $editingName)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .focused($nameFocused)
                .onSubmit { onRename(editingName); onClose() }
                .frame(maxWidth: 300)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 5), spacing: 20) {
                ForEach(apps) { app in
                    AppIconView(item: app, iconSize: 72, selectedAppID: $selectedAppID)
                }
            }
            .padding(24)
        }
        .padding(40)
        .frame(minWidth: 600, minHeight: 400)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                )
        )
        .onAppear {
            if autoFocusName {
                // One tick so the field is in the hierarchy before we focus it.
                DispatchQueue.main.async {
                    nameFocused = true
                }
            }
        }
        .onExitCommand(perform: { onRename(editingName); onClose() })
    }
}
