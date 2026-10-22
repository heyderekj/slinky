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
            "Press ⌘N or the + button and paste. Slinky turns the value into dots straight away, says what it looks like, and suggests where it goes. Change anything with the chips, then press Return.",
            "You can also press ⌘V anywhere in the window (when you're not typing in a field), or drop text on it. In a project, adding puts a variable in that project.",
            "Closed Add Item by accident? It keeps what you typed until you save, discard it, or Slinky locks. Locking clears it.",
            "Drop a project folder or a .env file on the Projects heading (or anywhere in the sidebar) to make a project. Slinky reads the .env files, including apps inside the folder, guesses each file's environment, and tells you if git could commit them. You see what it found before anything is saved.",
            "If you paste something that's already saved, Slinky tells you where. You can still save it again.",
        ]),
        Topic(symbol: "note.text", title: "Notes, links and icons", body: [
            "Add a note or a link with the chips under the value, or later with Edit. Links open in your browser with Open in the details on the right.",
            "Slinky shows each service's icon: its Mac app if you have it, otherwise its logo, otherwise initials. It works this out from the name, the website and the link, never the value. On Macs with Apple Intelligence, it can also ask the on-device model about names it doesn't know.",
            "Choose a different icon by clicking the icon in the details, or with Choose Icon… in an item's menu: any app on your Mac, any service Slinky knows, or initials.",
            "Load icons from websites, in Settings › General, is off until you turn it on. With it on, Slinky asks an item's website for its icon. With it off, you can still load one item's icon from its details.",
        ]),
        Topic(symbol: "terminal", title: "The slinky command", body: [
            "Install it in Settings › Command Line & Agents. Then slinky run -- npm run dev starts your app with the project's variables, after Touch ID, with no .env file on disk.",
            "slinky xcconfig writes an .xcconfig for an Xcode build. slinky run --file \"App Store Connect API key\" hands a command a secret file as a private temp file, deleted when it ends.",
            "Turn on loading in Settings and cd into a linked project: its variables load into that shell, and unload when you leave.",
            "The command asks Slinky, and Slinky asks you. Your own approvals are remembered for an hour; an agent's never are.",
        ]),
        Topic(symbol: "sparkles", title: "AI agents", body: [
            "Connect Claude Code, Cursor, Codex or Claude in Settings › Command Line & Agents. They see names, never values.",
            "To use a secret, an agent runs its command through slinky run, and you approve it with Touch ID, seeing the command. Live keys, anything marked never for agents, shells, inline code, and tools that send things off your Mac are held back.",
            "When an agent needs a key Slinky doesn't have, Slinky opens Add Item with the name filled in. Paste it there, not in the chat.",
            "Activity (the clock at the bottom of the sidebar) shows what was copied, used or imported, when, and by whom. Names only.",
        ]),
        Topic(symbol: "heart.text.square", title: "Health", body: [
            "Slinky looks for exact copies of your saved values in linked projects and their git history, AI tools' saved conversations, and your shell history. It reads them on this Mac and reports names and places only.",
            "A .env in a project can move into Slinky in one click: its variables are saved, a .env.example with names only is written, and the file goes to the Trash. History lines with a value can be removed.",
            "Stop Commits with Secrets, in a project's Import menu, checks each commit for saved values before it's made.",
            "Make New Key on GitHub… opens the page where you make keys, and Edit to paste the new one. The old one waits in Recently Deleted, and projects using it get the new one.",
        ]),
        Topic(symbol: "apple.logo", title: "Apple developer files", body: [
            "Drop an App Store Connect key (.p8), a certificate or a service-account JSON on the library, or use File › Add Secret File…. It's kept in the vault, up to 256 KB.",
            "Add the Issuer ID to an App Store Connect key, then Save a notarytool Profile: notarize with --keychain-profile and no .p8 lying in a folder.",
            "App-specific passwords (for notarization) are recognised when you paste them.",
        ]),
        Topic(symbol: "icloud.and.arrow.up", title: "Sending to your host", body: [
            "Share › Send to Host… in a project sends its variables to Vercel, Netlify, Cloudflare or Fly through their own command-line tools, signed in as you. You see the names first, and Touch ID confirms it.",
            "Compare shows which names the host has and Slinky doesn't, and the other way round. Never values.",
        ]),
        Topic(symbol: "square.and.arrow.down.on.square", title: "Importing", body: [
            "Bring keys over from another app with File › Import… (⇧⌘I), or drop the export on the window. Slinky reads a .1pux export from 1Password, a CSV from Apple Passwords, Bitwarden, LastPass, KeePass or a spreadsheet of keys, or a text file of codes or KEY=value lines.",
            "Slinky picks out API keys, tokens, backup codes and recovery keys, including keys in notes, and skips website passwords, which belong in Apple Passwords. You choose what comes in and can rename things first. Things already in Slinky start unchecked.",
            "Changed your mind? Undo (⌘Z) takes the whole import back.",
            "Export files aren't encrypted. Slinky can move the file to the Trash for you once the import is saved.",
        ]),
        Topic(symbol: "folder", title: "Projects", body: [
            "Link the project folder and Slinky reads its example files (.env.example, .sample, .template) to show which variables are missing.",
            "Update from Folder… (in the project's Import menu, or drop the folder or a .env file on the project) shows what's new, what changed and what's the same, environment by environment. Only what you check is saved, and Undo takes it back.",
            "Share › Copy as .env puts one environment's lines on the clipboard, for pasting into a host's dashboard. Share › Save .env.example writes the names only, with no values, so it's safe to commit.",
            "Slinky changes files in your project folder only when you ask: Save .env.example, Move into Slinky, and Stop Commits with Secrets.",
        ]),
        Topic(symbol: "doc.on.doc", title: "Copying", body: [
            "Press ⌥⌘K anywhere for Quick Access. Type to find something, then press Return to copy it.",
            "What Slinky copies is marked private, so clipboard history apps skip it and it doesn't go to your other devices. The clipboard clears after 60 seconds, or the time you choose in Settings, if you haven't copied anything else.",
            "Copying a recovery code crosses it off, since each code works once.",
        ]),
        Topic(symbol: "trash", title: "Recently Deleted", body: [
            "Deleting moves things to Recently Deleted, with Undo straight away. They stay there for 30 days, then they're deleted for good.",
            "Restore puts something back where it was. Delete Now and Empty delete for good, after you confirm.",
        ]),
        Topic(symbol: "lock", title: "Locking", body: [
            "Slinky opens with Touch ID. It locks when your screen locks, when your Mac sleeps, after 10 minutes away, and after 12 hours. Change these in Settings › Security.",
            "Lock it yourself with the switch at the top right, from the menu bar, or with ⌃⌘L.",
        ]),
        Topic(symbol: "lifepreserver", title: "Your Recovery Key", body: [
            "Slinky shows your Recovery Key once, when you save your first item. It opens your vault on another Mac, or if Touch ID stops working.",
            "Print it or keep it in Apple Passwords. Slinky doesn't keep a copy. If you lose it, make a new one in Settings › Recovery Key while Slinky is unlocked.",
            "Recovery keys you save for other accounts show up in Health until you print them or mark that you have a copy somewhere else.",
        ]),
        Topic(symbol: "square.stack.3d.up", title: "Shortcuts", body: [
            "Slinky adds four actions to the Shortcuts app: Add to Slinky, Copy from Slinky, Open Quick Access and Lock Slinky.",
            "Copy from Slinky asks for Touch ID every time and never hands the value to the shortcut.",
        ]),
        Topic(symbol: "internaldrive", title: "Where your things live", body: [
            "In one encrypted file on this Mac. There's no account and nothing goes to a server.",
            "Slinky goes online for two things: a daily check with GitHub for a newer version, and, only if you turn on Load icons from websites, a request to each saved website for its icon. Both are in Settings › General. When you choose Send to Host, that host's own tool sends the values you picked to that service.",
            "Optional, in Settings › General: reminders as Mac notifications (names only), and an offer to save a key you copy in another app (Slinky checks its shape and keeps nothing unless you choose Save).",
            "Time Machine backs the file up like any other. It stays encrypted, and only your Touch ID or your Recovery Key opens it.",
            "File › Export Backup… saves your whole vault as one encrypted file to keep somewhere else. It opens only with the Recovery Key you have when you make it. Restore it with File › Restore from Backup…, which replaces the vault on this Mac.",
        ]),
        Topic(symbol: "envelope", title: "Questions", body: [
            "Write to derek@testamentmade.com. Slinky is free and open source, made by Testament Made, LLC.",
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
