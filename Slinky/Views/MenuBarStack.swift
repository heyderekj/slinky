import SlinkyCoreShared
import SwiftUI

/// Layout F: the menu bar as a stack of small glass cards.
struct MenuBarStack: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 8) {
            card {
                HStack(spacing: 10) {
                    Circle().fill(model.isUnlocked ? Color.green : Color.orange).frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.isUnlocked ? "Unlocked" : "Locked").font(.headline)
                        Text(model.isUnlocked ? "Locks after 10 quiet minutes, or on sleep" : "Touch ID to peek")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.isUnlocked {
                        Button("Lock Now") { model.lock(reason: .manual) }.buttonStyle(.glass).controlSize(.small)
                    } else {
                        Button("Unlock…") { model.unlock() }.buttonStyle(.glassProminent).controlSize(.small)
                    }
                }
            }
            card {
                Button {
                    QuickAccess.shared.show()
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Quick Access")
                        Spacer()
                        Text("⌥⌘K").foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().opacity(0.5)
                Button {
                    open()
                    model.tuckPrefill = ""
                    model.tuckProject = nil
                    model.showTuck = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Tuck It Away…")
                        Spacer()
                        Text("⌘N").foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!model.isUnlocked)
            }
            if model.isUnlocked, !model.document.projects.isEmpty {
                card {
                    Text("Projects").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    FlowChips(items: model.document.projects.map { ($0.id, $0.name) }) { id in
                        model.selection = .project(id)
                        open()
                    }
                }
            }
            HStack {
                Button("Open Slinky") { open() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
        }
        .padding(10)
        .frame(width: 320)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func open() {
        openWindow(id: "main")
        NSApp.activate()
    }
}

/// Wrapping row of pill buttons.
struct FlowChips: View {
    let items: [(UUID, String)]
    let action: (UUID) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.0) { id, name in
                Button(name) { action(id) }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
