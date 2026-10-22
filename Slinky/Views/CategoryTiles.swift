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
                tile(.library(.all), "All", "square.grid.2x2", .accentColor, count: libraryCount(.all))
                tile(.library(.keys), "Keys", "key", Color(nsColor: .systemBlue), count: libraryCount(.keys))
            }
            GridRow {
                tile(.library(.codes), "Codes", "number", Color(nsColor: .systemYellow), count: libraryCount(.codes))
                tile(.library(.recoveryKeys), "Recovery Keys", "lifepreserver", Color(nsColor: .systemPurple),
                     count: libraryCount(.recoveryKeys))
            }
            GridRow {
                tile(.attention, "Health", "heart", Color(nsColor: .systemPink), count: model.healthCount,
                     needsYou: model.healthCount > 0)
                tile(.trash, "Deleted", "trash", Color(nsColor: .systemGray), count: model.document.trashed.count)
            }
        }
        // Each row as tall as its tallest tile, and no taller.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ item: SidebarItem, _ title: String, _ symbol: String, _ tint: Color, count: Int,
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

/// One tile: a colored circle with the place's symbol, its count, its name. Selected, it fills with the accent
/// and the circle turns white, the way Passwords marks where you are.
struct CategoryTile: View {
    let title: String
    let symbol: String
    let tint: Color
    let count: Int
    /// The count turns amber: something here needs a person.
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
                        .foregroundStyle(selected ? tint : Color.white)
                        .frame(width: 28, height: 28)
                        .background(selected ? Color.white : tint, in: .circle)
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
        if selected { return .accentColor }
        return Color.primary.opacity(hovering ? 0.09 : 0.055)
    }

    private var countStyle: Color {
        if selected { return Color.onAccent.opacity(0.85) }
        return needsYou ? .attention : .secondary
    }
}
