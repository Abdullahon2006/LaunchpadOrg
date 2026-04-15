import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.7))
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .focused(focused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(.white.opacity(0.15))
        )
        .frame(maxWidth: 260)
    }
}
