import SlinkyCoreShared
import SwiftUI

/// An item's icon: its Mac app's icon when installed, else the service's logo on its brand color in the same
/// squircle, else initials (Monogram). Sized like a Mac app icon so a list of them reads as a row of apps.
struct ServiceIcon: View {
    var subject: IconSubject
    var size: CGFloat = 30

    var body: some View {
        let resolver = IconResolver.shared
        Group {
            switch resolver.resolve(subject) {
            case let .app(image):
                // App icons have their own padding in the canvas; scale up a touch so they line up with tiles.
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size * 1.14, height: size * 1.14)
                    .frame(width: size, height: size)
            case let .website(image):
                // A site's icon can be any shape, so it sits on a white tile like the others.
                let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.14)
                    .frame(width: size, height: size)
                    .background(Color.white, in: shape)
                    .overlay(shape.strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                    .clipShape(shape)
            case let .logo(service):
                LogoTile(service: service, size: size)
            case let .monogram(text):
                Monogram(text: text, size: size)
            }
        }
        .accessibilityHidden(true)
        .task(id: subject) {
            resolver.guessIfNeeded(subject)
            resolver.fetchIfAllowed(subject)
        }
    }
}

/// A bundled service logo: the glyph in white (or near-black on light brands) on its brand color.
struct LogoTile: View {
    var service: Service
    var size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        let brand = Color(hex: service.color ?? 0x4A7AA3)
        ZStack {
            shape.fill(brand)
            shape.fill(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0)], startPoint: .top, endPoint: .center))
            if let name = service.logoName {
                Image(name)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(service.prefersDarkGlyph ? Color.black.opacity(0.82) : Color.white)
                    .frame(width: size * 0.56, height: size * 0.56)
            }
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.14)], startPoint: .top, endPoint: .bottom),
                                    lineWidth: max(0.5, size * 0.02)))
        .shadow(color: .black.opacity(0.12), radius: size * 0.08, y: size * 0.04)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
