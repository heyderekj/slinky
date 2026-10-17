import SwiftUI

// Slinky runs on macOS 15 Sequoia and later. Liquid Glass is a macOS 26 Tahoe look, so every glass surface
// and glass button goes through these: real glass on Tahoe, Apple's own standard look on Sequoia
// (a frosted material, bordered buttons). Never an imitation of glass.
extension View {
    /// A glass surface in `shape` on Tahoe; the regular frosted material with a hairline edge on Sequoia.
    @ViewBuilder
    func glass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        }
    }

    /// The glass button style on Tahoe; the standard bordered style on Sequoia.
    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// The prominent glass button style on Tahoe; the standard prominent style on Sequoia.
    @ViewBuilder
    func glassProminentButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// An SF Symbol that draws itself in on Tahoe; a plain fade on Sequoia.
    @ViewBuilder
    func drawOnTransition() -> some View {
        if #available(macOS 26.0, *) {
            transition(.symbolEffect(.drawOn))
        } else {
            transition(.opacity)
        }
    }
}
