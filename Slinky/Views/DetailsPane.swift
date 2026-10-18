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

/// The left sidebar's look on Tahoe: inset from the window edges, with corners concentric with the window's,
/// so the gap stays even all the way round the corner instead of closing up at it.
private let paneInset: CGFloat = 8

private struct PaneGlass: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glass(in: ConcentricRectangle(corners: .concentric(minimum: 12), isUniform: true))
        } else {
            Color.clear.glass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct DetailsPaneLayout<Pane: View>: ViewModifier {
    let isPresented: Bool
    let width: CGFloat
    let pane: Pane

    func body(content: Content) -> some View {
        // Like the left sidebar on Tahoe, the panel floats over the content rather than sitting beside it: the
        // list's surface runs on underneath the glass (no seam at the panel's edge), and opening only slides the
        // panel in while the list's rows make room, instead of rebuilding a row of views.
        content
            .shrinkable()
            .safeAreaPadding(.trailing, isPresented ? width + paneInset : 0)
            .overlay(alignment: .trailing) {
                if isPresented {
                    pane
                        .frame(width: width)
                        .frame(maxHeight: .infinity)
                        .padding(.bottom, paneInset)
                        // The panel runs up under the toolbar, like the left sidebar; what's in it starts below.
                        .background {
                            PaneGlass()
                                .padding(.vertical, paneInset)
                                .ignoresSafeArea(edges: .top)
                        }
                        .padding(.trailing, paneInset)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.smooth(duration: 0.32), value: isPresented)
    }
}
