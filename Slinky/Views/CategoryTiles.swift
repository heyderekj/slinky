import SlinkyCoreShared
import SwiftUI

/// The top of the sidebar, like Apple Passwords: a grid of tiles, each a kind of item (or Health, or Deleted) with
/// its count. Always all six, so nothing jumps around as they fill up. Projects and Activity are rows below. Names
/// are short to fit a tile ("Keys"); the toolbar title above the list says the full name ("Keys & Tokens").
struct CategoryGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // The kinds of item first (like Passwords' Passkeys, Codes, Wi-Fi), then Health and Deleted (its Security
        // and Deleted).
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                tile(.library(.all), "All", "square.grid.2x2", .glacier, count: libraryCount(.all))
                tile(.library(.keys), "Keys", "key", .sky, count: libraryCount(.keys))
            }
            GridRow {
                tile(.library(.codes), "Codes", "number", .mint, count: libraryCount(.codes))
                tile(.library(.recoveryKeys), "Recovery", "lifepreserver", .violet,
                     count: libraryCount(.recoveryKeys))
            }
            GridRow {
                tile(.attention, "Health", "heart", .pink, count: model.healthCount,
                     needsYou: model.healthCount > 0)
                tile(.trash, "Deleted", "trash", .slate, count: model.document.trashed.count)
            }
        }
        // Each row as tall as its tallest tile, and no taller.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ item: SidebarItem, _ title: String, _ symbol: String, _ tint: TileColor, count: Int,
                      needsYou: Bool = false) -> some View {
        CategoryTile(title: title, symbol: symbol, tint: tint, count: count, needsYou: needsYou,
                     selected: model.selection == item) {
            model.selection = item
        }
    }

    private func libraryCount(_ filter: LibraryFilter) -> Int {
        let d = model.document
        switch filter {
        case .all: return d.keys.count + d.codeSets.count + d.kept.count + d.secretFiles.count
        case .keys: return d.keys.count + d.secretFiles.count
        case .codes: return d.codeSets.count
        case .recoveryKeys: return d.kept.count
        }
    }
}

/// One tile: a colored circle with the place's symbol, its count, its name. Selected, it fills with its own color
/// and the circle turns white, the way Passwords marks where you are.
/// Slinky's own colors, from the monogram palette (Components.swift), not the system's: a light top and a deep
/// bottom for the circle's gradient, like the monograms and the app icon. The deep color carries white text, so
/// it's also the selected tile's fill.
struct TileColor {
    let top: Color
    let deep: Color

    static let glacier = TileColor(top: Color(red: 0.50, green: 0.89, blue: 0.95), deep: Color(red: 0.043, green: 0.498, blue: 0.561))   // #0b7f8f, the accent
    static let sky = TileColor(top: Color(red: 0.55, green: 0.76, blue: 0.98), deep: Color(red: 0.16, green: 0.42, blue: 0.84))
    static let mint = TileColor(top: Color(red: 0.56, green: 0.92, blue: 0.66), deep: Color(red: 0.08, green: 0.50, blue: 0.34))
    static let violet = TileColor(top: Color(red: 0.80, green: 0.64, blue: 1.00), deep: Color(red: 0.48, green: 0.26, blue: 0.84))
    static let pink = TileColor(top: Color(red: 1.00, green: 0.64, blue: 0.80), deep: Color(red: 0.80, green: 0.22, blue: 0.48))
    static let slate = TileColor(top: Color(red: 0.72, green: 0.78, blue: 0.83), deep: Color(red: 0.38, green: 0.44, blue: 0.50))
}

struct CategoryTile: View {
    let title: String
    let symbol: String
    let tint: TileColor
    let count: Int
    /// The count turns pink, Health's color: something here needs a person.
    var needsYou = false
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: symbol)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(selected ? tint.deep : Color.white)
                        .frame(width: 28, height: 28)
                        .background(in: .circle)
                        .backgroundStyle(selected ? AnyShapeStyle(Color.white)
                                                  : AnyShapeStyle(LinearGradient(colors: [tint.top, tint.deep], startPoint: .top, endPoint: .bottom)))
                    Spacer(minLength: 4)
                    Text(count, format: .number)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(countStyle)
                        .contentTransition(.numericText(value: Double(count)))
                        .animation(.snappy, value: count)
                }
                Spacer(minLength: 8)
                // Every name at the same size; a long one ("Recovery Keys") wraps rather than shrinking.
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(selected ? Color.onAccent : Color.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            // Both tiles in a row match the taller one, names along the bottom.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(fill, in: .rect(cornerRadius: 12, style: .continuous))
            .contentShape(.rect(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.smooth(duration: 0.2), value: selected)
        .accessibilityLabel(title)
        .accessibilityValue(needsYou ? "\(count), needs attention" : "\(count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var fill: Color {
        if selected { return tint.deep }
        return Color.primary.opacity(hovering ? 0.09 : 0.055)
    }

    private var countStyle: Color {
        if selected { return Color.onAccent.opacity(0.85) }
        return needsYou ? .health : .secondary
    }
}
