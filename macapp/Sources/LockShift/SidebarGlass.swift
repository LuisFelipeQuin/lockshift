import SwiftUI

/// A single glass surface keeps the sidebar readable over the map.
struct SidebarGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        surface(content)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 8)
    }

    @ViewBuilder
    private func surface(_ content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor))
        } else {
            translucentSurface(content)
        }
    }

    @ViewBuilder
    private func translucentSurface(_ content: Content) -> some View {
        // Xcode 16's SDK does not define glassEffect, even behind #available.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        } else {
            materialSurface(content)
        }
        #else
        materialSurface(content)
        #endif
    }

    private func materialSurface(_ content: Content) -> some View {
        content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}
