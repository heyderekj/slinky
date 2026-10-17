import SwiftUI

/// Help › Slinky Help. Plain answers, short sections, no jargon unless it's the thing's real name.
struct HelpView: View {
    private struct Topic: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let body: [String]
    }

    private let topics: [Topic] = [
        Topic(symbol: "square.grid.2x2", title: "What Slinky keeps", body: [
            "Keys & Tokens: API keys and access tokens your software and AI tools use.",
            "Projects: each app's .env variables, for Local, Preview and Production.",
            "Recovery: backup codes for two-step sign-in, and recovery keys that get you back into an account.",
            "Passwords belong in Apple Passwords. Slinky doesn't store crypto wallet recovery phrases, for your safety.",
        ]),
        Topic(symbol: "plus", title: "Adding things", body: [
            "Press ⌘N and paste. Slinky turns the value into dots straight away, says what it looks like, and suggests where it goes. Change anything with the chips, then press Return.",
            "Drop a project folder or a .env file on the sidebar to make a project. Slinky reads the .env files, guesses each file's environment, and tells you if git could commit them.",
            "If you paste something that's already saved, Slinky tells you where. You can still save it again.",
        ]),
        Topic(symbol: "square.and.arrow.down.on.square", title: "Switching from 1Password", body: [
            "Export from 1Password (File › Export, as a .1pux file), then choose File › Import from 1Password or CSV… (⇧⌘I) in Slinky. A CSV from Apple Passwords, Bitwarden or a spreadsheet of keys works too.",
            "Slinky picks out API keys, tokens, backup codes and recovery keys, and skips website passwords, which belong in Apple Passwords. You choose what comes in. Things already in Slinky start unchecked.",
            "Export files aren't encrypted. Slinky can move the file to the Trash for you after importing.",
        ]),
        Topic(symbol: "folder", title: "Projects", body: [
            "Link the project folder and Slinky reads its .env.example to show which variables are missing.",
            "Share › Copy as .env puts one environment's lines on the clipboard, for pasting into a host's dashboard. Share › Save .env.example writes the names only, with no values, so it's safe to commit.",
            "Slinky never changes files in your project folder unless you choose Save .env.example.",
        ]),
        Topic(symbol: "doc.on.doc", title: "Copying", body: [
            "Press ⌥⌘K anywhere for Quick Access. Type to find something, then press Return to copy it.",
            "What Slinky copies is marked private, so clipboard history apps skip it and it doesn't go to your other devices. The clipboard clears after 60 seconds, or the time you choose in Settings, if you haven't copied anything else.",
            "Copying a recovery code crosses it off, since each code works once.",
        ]),
        Topic(symbol: "lock", title: "Locking", body: [
            "Slinky opens with Touch ID. It locks when your screen locks, when your Mac sleeps, after 10 minutes away, and after 12 hours. Change these in Settings › Security.",
            "Lock it yourself with the switch at the top right, from the menu bar, or with ⌃⌘L.",
        ]),
        Topic(symbol: "lifepreserver", title: "Your Recovery Key", body: [
            "Slinky shows your Recovery Key once, when you save your first item. It opens your vault on another Mac, or if Touch ID stops working.",
            "Print it or keep it in Apple Passwords. Slinky doesn't keep a copy. If you lose it, make a new one in Settings › Recovery Key while Slinky is unlocked.",
            "Recovery keys you save for other accounts show up in Needs Attention until you print them or mark that you have a copy somewhere else.",
        ]),
        Topic(symbol: "square.stack.3d.up", title: "Shortcuts", body: [
            "Slinky adds four actions to the Shortcuts app: Add to Slinky, Copy from Slinky, Open Quick Access and Lock Slinky.",
            "Copy from Slinky asks for Touch ID every time and never hands the value to the shortcut.",
        ]),
        Topic(symbol: "internaldrive", title: "Where your things live", body: [
            "In one encrypted file on this Mac. There's no account and nothing goes to a server.",
            "The only time Slinky goes online is a daily check with GitHub for a newer version. Turn it off in Settings › General.",
            "Time Machine backs the file up like any other. It stays encrypted, and only your Touch ID or your Recovery Key opens it.",
        ]),
        Topic(symbol: "envelope", title: "Questions", body: [
            "Write to help@slinkyfiles.com. Slinky is free and open source, made by Testament Made, LLC.",
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    KeyholeMark(size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Slinky Help").font(.title2.weight(.bold))
                        Text("Slinky keeps secrets out of files.").foregroundStyle(.secondary)
                    }
                }
                ForEach(topics) { topic in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(topic.title, systemImage: topic.symbol)
                            .font(.headline)
                        ForEach(topic.body, id: \.self) { line in
                            Text(line)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.paper.opacity(0.7), in: .rect(cornerRadius: 16))
                }
            }
            .padding(24)
        }
        .frame(width: 560, height: 640)
    }
}
