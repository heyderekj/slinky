import AppKit
import SlinkyCoreShared
import SwiftUI

/// Choose Icon…: any app on this Mac, any service Slinky knows, or initials.
struct ChooseIconView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let ref: LibraryRef
    @State private var query = ""
    @State private var apps: [InstalledApp] = []

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 100), spacing: 8, alignment: .top)]

    var body: some View {
        let subject = model.iconSubject(ref) ?? IconSubject(name: "")
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ServiceIcon(subject: subject, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Choose Icon").font(.headline)
                    Text(subject.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                TextField("Search apps and services", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if query.isEmpty {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                            tile("Automatic", selected: subject.choice == nil || subject.choice == .automatic) {
                                ServiceIcon(subject: IconSubject(name: subject.name, from: subject.from, provider: subject.provider,
                                                                 link: subject.link, note: subject.note), size: 40)
                            } pick: { pick(nil) }
                            tile("Initials", selected: subject.choice == .monogram) {
                                Monogram(text: subject.provider ?? subject.from ?? subject.name, size: 40)
                            } pick: { pick(.monogram) }
                        }
                    }
                    let foundApps = apps.filter { matches($0.name) }
                    if !foundApps.isEmpty {
                        section("Apps on This Mac") {
                            ForEach(foundApps) { app in
                                tile(app.name, selected: subject.choice == .app(app.bundleID)) {
                                    AppIconImage(bundleID: app.bundleID, size: 40)
                                } pick: { pick(.app(app.bundleID)) }
                            }
                        }
                    }
                    let services = ServiceCatalog.all.filter { $0.hasLogo && (matches($0.name) || $0.aliases.contains(where: matches)) }
                    if !services.isEmpty {
                        section("Services") {
                            ForEach(services) { s in
                                tile(s.name, selected: subject.choice == .service(s.id)) {
                                    LogoTile(service: s, size: 40)
                                } pick: { pick(.service(s.id)) }
                            }
                        }
                    }
                }
                .padding(16)
            }
            Divider()
            HStack {
                Text("Logos belong to their owners.").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).glassProminentButton().dialogButtons()
            }
            .padding(12)
        }
        .frame(width: 560, height: 520)
        .task { apps = await InstalledApp.scan() }
    }

    private func matches(_ text: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || text.localizedCaseInsensitiveContains(q)
    }

    private func pick(_ choice: IconChoice?) {
        model.setIcon(choice, for: ref)
        dismiss()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) { content() }
        }
    }

    private func tile<Icon: View>(_ name: String, selected: Bool, @ViewBuilder icon: () -> Icon, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            VStack(spacing: 6) {
                icon()
                Text(name).font(.caption).lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .padding(6)
            .background(selected ? Color.accentColor.opacity(0.16) : Color.clear, in: .rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct AppIconImage: View {
    let bundleID: String
    let size: CGFloat

    var body: some View {
        if let image = IconResolver.shared.appIcon(bundleID) {
            Image(nsImage: image).resizable().frame(width: size * 1.14, height: size * 1.14).frame(width: size, height: size)
        } else {
            Monogram(text: bundleID, size: size)
        }
    }
}

struct InstalledApp: Identifiable, Hashable, Sendable {
    var id: String { bundleID }
    let name: String
    let bundleID: String

    /// The apps in the usual places, by name. Read from their Info.plist; nothing is sent anywhere.
    static func scan() async -> [InstalledApp] {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                        (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
            var seen = Set<String>()
            var out: [InstalledApp] = []
            for dir in dirs {
                guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                for file in names where file.hasSuffix(".app") {
                    let url = URL(fileURLWithPath: dir).appendingPathComponent(file)
                    guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, seen.insert(id).inserted else { continue }
                    let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                        ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                        ?? String(file.dropLast(4))
                    out.append(InstalledApp(name: name, bundleID: id))
                }
            }
            return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }.value
    }
}
