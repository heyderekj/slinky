import SwiftUI

/// The right sidebar with an item's or a variable's details, drawn to match the left one: a full-height glass
/// panel inset from the window's edges, running up under the toolbar.
///
/// Not the system `.inspector`. On Tahoe it counts its own width twice when macOS works out how wide the
/// content must be (once as the content's inset, once as its own column), so at the window's smaller sizes the
/// content demanded more than the window had: the left sidebar was squeezed and pushed off the left edge, or the
/// inspector stopped short of the right one. This pane is plain layout: its width comes out of the list, and the
/// numbers always fit (left sidebar ~258 + content 300 + details 280 + insets < the 880 minimum).
extension View {
    func detailsPane<Pane: View>(isPresented: Binding<Bool>, width: CGFloat = 280, @ViewBuilder pane: () -> Pane) -> some View {
        modifier(DetailsPaneLayout(isPresented: isPresented.wrappedValue, width: width, pane: pane()))
    }

    /// The content can shrink to 300 points, so it never crowds the left sidebar below its minimum.
    func shrinkable() -> some View {
        frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The left sidebar's look on Tahoe: inset from the window edges, continuous corners.
private let paneInset: CGFloat = 8
private let paneShape = RoundedRectangle(cornerRadius: 18, style: .continuous)

private struct DetailsPaneLayout<Pane: View>: ViewModifier {
    let isPresented: Bool
    let width: CGFloat
    let pane: Pane

    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            content.shrinkable()
            if isPresented {
                pane
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, paneInset)
                    // The panel itself runs up under the toolbar, like the left sidebar; what's in it starts below.
                    .background {
                        Color.clear
                            .glass(in: paneShape)
                            .padding(.vertical, paneInset)
                            .ignoresSafeArea(edges: .top)
                    }
                    .padding(.trailing, paneInset)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.88), value: isPresented)
    }
}
