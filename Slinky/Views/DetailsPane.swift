import SwiftUI

/// The details pane on the right of the library and a project: a floating glass panel inside the content
/// area, mirroring the sidebar. Not the system `.inspector`, which takes its width from the sidebar: at the
/// window's smaller sizes that squeezed the sidebar below its minimum and pushed its content off the left.
/// This pane takes its width from the list instead, and the sidebar is never touched.
extension View {
    func detailsPane<Pane: View>(isPresented: Bool, width: CGFloat = 300, @ViewBuilder pane: () -> Pane) -> some View {
        modifier(DetailsPaneLayout(isPresented: isPresented, width: width, pane: pane()))
    }
}

private struct DetailsPaneLayout<Pane: View>: ViewModifier {
    let isPresented: Bool
    let width: CGFloat
    let pane: Pane

    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            content
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            if isPresented {
                pane
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .glass(in: .rect(cornerRadius: 18))
                    .padding([.trailing, .bottom], 10)
                    .padding(.top, 4)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.88), value: isPresented)
    }
}
