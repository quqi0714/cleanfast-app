import SwiftUI

struct GlassCardView<Content: View>: View {
    var cornerRadius: CGFloat = 28
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: shape)
            .overlay(
                shape
                    .stroke(Color.white.opacity(0.6), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 20, x: 0, y: 8)
    }
}
