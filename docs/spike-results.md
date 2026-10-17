# Feasibility test results (2026-10-16)

**Verdict: go.** All seven checks passed on Derek's Mac without a paid Apple Developer account. Slinky's planned storage design (Tier 1) works as designed: an encrypted vault whose key is wrapped by a Secure Enclave key, plus a signature-checked socket between the app and the CLI. No fallbacks are needed.

**Setup:**
- MacBook with Apple M2, macOS 26.5.2, Xcode 26.6, Swift 6.3.3.
- Signed with the free Apple Development identity, hardened runtime on, no entitlements (so no `get-task-allow`). Gatekeeper rejects the build as expected, because it isn't notarized.
- Code: `spike/` (`./build-app.sh`, `./package-like-user.sh`).

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Secure Enclave key + Touch ID, from the app | ✅ Pass | The CryptoKit `SecureEnclave.P256.KeyAgreement` key was created **without a provisioning profile**. Unwrap asked for Touch ID (2.6 s) and the vault key round-tripped (`d211c4241487` matches). A second unwrap in the same session took 0.0 s with no prompt. |
| 2 | Touch ID from the CLI on its own | ✅ Pass | `slinky-spike create-own` / `unwrap-own`: Touch ID appeared for the Terminal tool, and `e87cf9d2299b` matches. |
| 3 | No keychain prompt after a rebuild | ✅ Pass | Changed the code, rebuilt, re-signed (new CDHash `ebac9381…`) and relaunched. Reading the login-keychain item returned instantly with no dialog. Keychain access follows the signing identity, not the exact build. |
| 4 | Impostor CLI refused | ✅ Pass | The genuine CLI was accepted. The same binary re-signed ad-hoc under the same identifier was refused: `-67050`, "no team (ad-hoc)". |
| 5 | Sees who's asking | ✅ Pass | From inside a Claude Code session the app saw: `Claude › disclaimer › claude › zsh › slinky-spike`. |
| 6 | Installs like Dinky/Binky | ✅ Pass | The quarantined zip in Downloads was blocked on first open. One **Open Anyway** let it run (quarantine flag `0083` changed to `00c3`, user-approved). The embedded CLI then ran through a symlink with **no second block**. |
| 7 | Screen lock requires Touch ID again | ✅ Pass | The app logged "Locked (screen locked)". The next unwrap waited for Touch ID (4.7 s). |

## Things learned
- **Team ID is `B3U6BXA8KP`.** The `QHT464P5ZY` in the certificate's name is a personal ID, not the team. Code-signing requirements must use `certificate leaf[subject.OU] = "B3U6BXA8KP"`.
- **Session reuse works** by passing one `LAContext` into the Secure Enclave operations. Invalidating it on `com.apple.screenIsLocked`, sleep and display sleep makes the next use ask again.
- **The Secure Enclave key blob can sit in the legacy login keychain**, in an item created by the app. Other processes would trigger a keychain prompt with their own name.
- **The CLI needs nothing special.** It ships inside the app bundle, symlinked onto the PATH, and runs after the single Open Anyway.
- **Caveats still to test later:**
  - **Renewal:** whether keychain access survives renewing the Apple Development certificate (it should, since the requirement pins the team and identifier, not the certificate).
  - **macOS 27:** install behavior, in a VM.
  - **Macs without Touch ID:** the password fallback.

## Leftovers from the test (safe to delete)
- `~/Downloads/SlinkySpike.app` and `~/Downloads/SlinkySpike-test.zip`
- `~/Library/Application Support/SlinkySpike/`
- Two login-keychain items: service `com.slinky.spike` and `com.slinky.spike.cli`
- Two test keys in the Secure Enclave. They're unreachable once the keychain items are deleted.

## Next
Scaffold the real project (step 1 of "After Derek reviews the results" in the build plan). Use the Apple Development identity and team `B3U6BXA8KP`, Manual signing, hardened runtime, and no restricted entitlements.
