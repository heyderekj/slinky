---
layout: ../../layouts/Guide.astro
title: Keep your App Store Connect API key safe
seo: Where to keep an App Store Connect API key (.p8) · Slinky
description: Apple lets you download an App Store Connect API key (.p8) only once. Here’s where to keep it, how to notarize without the file lying in a folder, and how Slinky stores it in an encrypted vault.
lede: Apple lets you download an App Store Connect API key once. It usually lands in Downloads as AuthKey_XXXXXXXXXX.p8 and stays there, next to everything else.
faq:
  - ["What if I lose the .p8 file?", "Apple won’t let you download it again. Revoke the key in App Store Connect and make a new one, then update everything that used it."]
  - ["Can I keep an app-specific password in Slinky too?", "Yes. Slinky recognises app-specific passwords when you paste them, for tools that still sign in with your Apple Account."]
  - ["How big a file can Slinky keep?", "Secret files up to 256 KB, such as .p8 keys, certificates and service-account JSON."]
---

## What the key is

An App Store Connect API key has three parts:

- **The private key**, the `.p8` file. This is the secret. Anyone with it can act as your team in App Store Connect, as far as the key’s role allows.
- **The Key ID**, which is in the file name.
- **The Issuer ID**, shown at the top of the Keys page in App Store Connect.

Tools like `notarytool`, `altool`, fastlane and Xcode Cloud scripts need all three.

## Keep the file out of folders

- Don’t leave it in Downloads, the project folder or a shared drive. Move it somewhere encrypted the day you download it.
- Give the key the narrowest role that works (Developer for notarization, not Admin).
- Don’t commit it. Add `*.p8` to `.gitignore` in any project that touches it.

## Notarize without the file

`notarytool` can save your credentials in the login keychain once, as a profile:

```bash
xcrun notarytool store-credentials "MyProfile" \
  --key AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer <issuer-id>
```

After that, `xcrun notarytool submit App.zip --keychain-profile "MyProfile" --wait` works without the `.p8` anywhere on disk.

## How Slinky does it

- **Drop the .p8 on Slinky**, or use File › Add Secret File…. It goes into the encrypted vault, and you can move the original to the Trash.
- **Add the Issuer ID**, then **Save a notarytool Profile**. Slinky runs `store-credentials` for you, so you notarize with `--keychain-profile` and the file never sits in a folder. From Terminal: `slinky notarize-profile MyProfile`.
- **Hand the file to a command when one needs it.** `slinky run --file "App Store Connect API key" -- fastlane release` gives the command a private temporary copy, deleted when the command ends.
- **Xcode builds**: `slinky xcconfig` writes an `.xcconfig` with a project’s variables for a build.
