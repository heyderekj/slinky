import SwiftUI

/// The right sidebar with an item's or a variable's details, drawn to match the left one: a glass panel inset
/// from the window's edges, starting below the toolbar.
///
/// Not the system `.inspector`. On Tahoe it counts its own width twice when macOS works out how wide the
/// content must be (once as the content's inset, once as its own column), so at the window's smaller sizes the
/// content demanded more than the window had: the left sidebar was squeezed and pushed off the left edge, or the
/// inspector stopped short of the right one. This pane is plain layout: its width comes out of the list, and the
/// numbers always fit (left sidebar ~260 + content 300 + details 280–340 + insets ≤ the window).
extension View {
    /// 340 wide, so its left edge lines up with the toolbar's search field above it. In a window too small for
    /// that and the list's 300, it narrows, down to 280.
    func detailsPane<Pane: View>(isPresented: Binding<Bool>, width: CGFloat = 340, @ViewBuilder pane: () -> Pane) -> some View {
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
    let idealWidth: CGFloat
    let pane: Pane
    @State private var available: CGFloat = 0

    init(isPresented: Bool, width: CGFloat, pane: Pane) {
        self.isPresented = isPresented
        self.idealWidth = width
        self.pane = pane
    }

    /// The ideal width, unless the content would drop below its 300.
    private var width: CGFloat {
        guard available > 0 else { return idealWidth }
        return min(idealWidth, max(280, available - 300 - paneInset * 2))
    }

    func body(content: Content) -> some View {
        // Like the left sidebar on Tahoe, the panel floats over the content rather than sitting beside it: the
        // list's surface runs on underneath the glass (no seam at the panel's edge), and opening only slides the
        // panel in while the list's rows make room, instead of rebuilding a row of views.
        content
            .shrinkable()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
            .safeAreaPadding(.trailing, isPresented ? width + paneInset : 0)
            .overlay(alignment: .trailing) {
                // Always there, slid off the edge when closed. Adding and removing it made the glass play its own
                // appear/disappear effect (a lighter, bluish flash as it closed); sliding glass that stays put doesn't.
                pane
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, paneInset)
                    // The panel starts below the toolbar, so the toolbar's buttons sit above it with room
                    // to breathe instead of on its top edge.
                    .padding(.top, paneInset)
                    .background {
                        PaneGlass()
                            .padding(.vertical, paneInset)
                    }
                    .padding(.trailing, paneInset)
                    .offset(x: isPresented ? 0 : width + paneInset * 3)
                    .allowsHitTesting(isPresented)
                    .accessibilityHidden(!isPresented)
            }
            .animation(.smooth(duration: 0.32), value: isPresented)
    }
}

/// The details pane with nothing picked, like Passwords' "No Item Selected": a large quiet symbol and a line.
struct NothingSelected: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "key.2.on.ring")
        } description: {
            Text(message)
        }
        .foregroundStyle(.secondary)
    }
}
