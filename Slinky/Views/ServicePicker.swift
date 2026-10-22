import SlinkyCoreShared
import SwiftUI

/// Where it lives: a row of services to scroll through, with search. The person's pick is the item's service
/// everywhere (its subtitle, its icon when that's automatic, sorting, and "Make New Key on …"). Slinky's own
/// best match, or Apple Intelligence's guess, goes first and is marked Suggested, but is never picked for you.
struct ServicePicker: View {
    @Binding var selection: String?
    /// The item as typed, for the suggestion.
    var subject: IconSubject
    var onPick: (String?) -> Void = { _ in }

    @State private var query = ""
    @FocusState private var searching: Bool

    var body: some View {
        let suggestion = IconResolver.shared.suggestion(for: IconSubject(name: subject.name, from: subject.from,
                                                                         provider: subject.provider, link: subject.link,
                                                                         note: subject.note))
        let list = services(suggestion: suggestion)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search services, like Cloudflare", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searching)
                    .onSubmit { if let first = list.first, !query.isEmpty { pick(first.id) } }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Clear Search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.paper, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1))

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 4) {
                        if query.isEmpty && selection != nil {
                            tile(id: nil, title: "None", badge: nil) {
                                Image(systemName: "circle.slash")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, height: 36)
                                    .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 9, style: .continuous))
                            }
                        }
                        ForEach(list) { s in
                            tile(id: s.id, title: s.name,
                                 badge: s.id == suggestion?.id && selection == nil && query.isEmpty ? "Suggested" : nil) {
                                if s.hasLogo { LogoTile(service: s, size: 36) } else { Monogram(text: s.name, size: 36) }
                            }
                            .id(s.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
                .frame(height: 78)
                .onAppear { if let selection { proxy.scrollTo(selection, anchor: .center) } }
                // Outside the scroller, so it wraps instead of running off the edge.
                .overlay(alignment: .leading) {
                    if list.isEmpty {
                        Text("No service called “\(query)”. Add a link instead, and Slinky shows that website.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 6)
                    }
                }
            }
        }
        .onAppear {
            // An unknown name gets one quiet on-device guess, shown only as a suggestion.
            IconResolver.shared.guessIfNeeded(IconSubject(name: subject.name, from: subject.from, provider: subject.provider,
                                                          link: subject.link))
        }
    }

    /// The pick first, then the suggestion, then everything else by name. Search matches names, aliases and sites.
    private func services(suggestion: Service?) -> [Service] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var all = ServiceCatalog.all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !q.isEmpty {
            all = all.filter { s in
                s.name.lowercased().contains(q) || s.aliases.contains { $0.lowercased().hasPrefix(q) }
                    || s.domains.contains { $0.hasPrefix(q) }
            }
            // Names that start with the search come first.
            return all.filter { $0.name.lowercased().hasPrefix(q) } + all.filter { !$0.name.lowercased().hasPrefix(q) }
        }
        let firsts = [selection, suggestion?.id].compactMap { $0 }
        let front = firsts.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.compactMap(ServiceCatalog.service(id:))
        return front + all.filter { !firsts.contains($0.id) }
    }

    private func pick(_ id: String?) {
        withAnimation(.snappy) { selection = id }
        query = ""
        onPick(id)
    }

    private func tile<Icon: View>(id: String?, title: String, badge: String?, @ViewBuilder icon: () -> Icon) -> some View {
        let selected = selection == id
        return Button { pick(id) } label: {
            VStack(spacing: 5) {
                icon()
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .padding(-3)
                            .opacity(selected ? 1 : 0)
                    }
                Text(badge ?? title)
                    .font(.caption2.weight(badge != nil || selected ? .semibold : .regular))
                    .foregroundStyle(badge != nil ? Color.accentColor : selected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 68, height: 72)
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(badge.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Shows where an item lives and opens the picker. A chip in Add Item; a quiet link in the details panel.
struct ServiceChip: View {
    @Binding var selection: String?
    var subject: IconSubject
    /// What Slinky matched on its own, shown until the person picks.
    var automatic: Service? = nil
    var inline = false
    var onPick: (String?) -> Void = { _ in }
    @State private var open = false

    var body: some View {
        let service = selection.flatMap(ServiceCatalog.service(id:)) ?? automatic
        Group {
            if inline {
                Button { open.toggle() } label: {
                    HStack(spacing: 3) {
                        Text(service?.name ?? "Where it lives?")
                            .lineLimit(1)
                            .frame(maxWidth: 130)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(service == nil ? Color.accentColor : .secondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Where it lives")
            } else {
                Button { open.toggle() } label: {
                    HStack(spacing: 6) {
                        if let service {
                            if service.hasLogo { LogoTile(service: service, size: 16) } else { Monogram(text: service.name, size: 16) }
                        } else {
                            Image(systemName: "building.2")
                        }
                        Text(service?.name ?? "Where it lives")
                            .lineLimit(1)
                            .frame(maxWidth: 160)
                    }
                }
                .buttonStyle(ChipButtonStyle(selected: selection != nil))
            }
        }
        .fixedSize()
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Where it lives").font(.headline)
                Text("The service where you manage it. Slinky uses it for the icon and for making a new key.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ServicePicker(selection: $selection, subject: subject) { id in
                    onPick(id)
                    open = false
                }
            }
            .padding(14)
            .frame(width: 440)
        }
    }
}
