# Slinky feasibility test (no paid Apple Developer account)

**Goal:** before building any real UI, prove on Derek's Mac that Slinky can protect secrets with Touch ID and install like Dinky and Binky, all without the $99 account. Each step is a pass/fail check with a fallback.

**What this Mac already has (checked 2026-10-16):**
- Xcode 26.6 and Swift 6.3.3 on macOS 26.5.2, Apple M2.
- Two **Apple Development** signing identities from the free Personal Team (team `QHT464P5ZY`, byderekj@icloud.com).

That certificate is the stable signing identity, so no self-signed certificate is needed. Apple-issued certificates identify the app by Team ID and bundle ID, so keychain access survives rebuilds and updates. The certificate itself renews yearly under the same team.

## The spike: one tiny app plus a CLI, about half a day

Make a throwaway project, `spike/SlinkySpike`: a menu-bar-less SwiftUI app with an embedded `slinky-spike` command-line tool, both signed with the Apple Development identity. No real UI, just buttons and printed results.

| # | Test | Pass looks like | If it fails |
|---|---|---|---|
| 1 | **Secure Enclave key with Touch ID.** CryptoKit `SecureEnclave.P256.KeyAgreement` with `.privateKeyUsage` + `.userPresence`, used to wrap and unwrap a random vault key (HPKE). | A Touch ID sheet appears, and the vault key comes back after you touch the sensor. | Store the vault key in the login keychain and put an app-level Touch ID check (`LAContext`) in front of it. |
| 2 | **Same, from the CLI.** Run `slinky-spike unwrap` in Terminal. | Touch ID appears for the Terminal command. | The CLI asks the app over a socket instead (the planned design anyway). |
| 3 | **Keychain survives a rebuild.** Store the Secure Enclave key blob in a login-keychain item, rebuild with a code change, then read it again. | No "wants to use your confidential information" prompt. | Expected only if signing is ad-hoc. Confirm the build used the Apple Development identity. |
| 4 | **Socket and peer check.** The app listens on a Unix socket in `~/Library/Application Support/SlinkySpike/`. The CLI connects; the app reads the caller's audit token and checks its code signature. | A genuine CLI is accepted, and a copied, re-signed or unsigned binary is refused. | Fall back to path plus code-hash checks. |
| 5 | **Who's asking.** From inside a Claude Code session, run the CLI. The app walks the parent processes. | It prints a chain like `claude › zsh › slinky-spike`. | Show the raw chain without friendly names. |
| 6 | **Install like a user.** Zip the app, download it in Safari from a GitHub draft release (or apply the quarantine attribute by hand), unzip, open, click "Open Anyway", then run the embedded CLI from Terminal through a symlink. | The app opens after one approval, and the CLI runs without a second block. | Ship the CLI through Homebrew's `binary` stanza, or have the app copy it out with an "Install Command Line Tool" button. |
| 7 | **Locks.** Lock the screen, sleep, then try to unwrap. | Slinky asks for Touch ID again. | Tune how the authentication context is invalidated. |

**Optional second path (the fully supported setup):** sign the spike with an Xcode **Personal Team provisioning profile** and use the data-protection keychain. This is the route Apple officially supports, and it works on Derek's own Mac. The catch is that the free profiles expire every 7 days, so it's for dogfooding, not shipping.

## Then: the first real slice

Only after tests 1, 3, 4 and 6 pass. Build order:
1. Repo scaffold from Binky: `Slinky.xcodeproj`, the `SlinkyCore` package (Shared · Vault · CLILib · CLI), CLAUDE.md, VOICE.md, agents.md.
2. Vault: encrypted file, Secure Enclave wrap, Recovery Key, auto-lock.
3. **Tuck It Away**, plus Kept / Keys / project variables. Pass the acceptance test: Derek's recovery key, personal API token and env secret each go to the right place in one paste.
4. `slinky run -- cmd` with masking, `import .env`, `check`, `ls`.
5. MCP: `list_secrets`, `check_env`, `request_secret`.
6. Approval card and Activity log.

Dogfood for two weeks on harvous, Dinky and Binky, then decide on the Developer ID and the public 1.0.

## Not testable on this Mac
- **macOS 27 behavior.** This Mac runs 26.5.2. Use a macOS 27 virtual machine (UTM or VirtualBuddy; Apple silicon runs them well) to test the install, Gatekeeper and first-run flows. VMs have no Touch ID or Secure Enclave, so the Touch ID tests stay on this Mac.
- **A fresh user's first run.** A second macOS user account on this Mac is the cheap stand-in.
- **Macs without Touch ID.** Check that `.userPresence` falls back to the Mac password. A clamshell-closed MacBook simulates this.
