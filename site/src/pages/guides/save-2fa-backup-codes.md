---
layout: ../../layouts/Guide.astro
title: Where to save two-factor backup codes
seo: Where to save 2FA backup codes and recovery keys · Slinky
description: When a website gives you backup codes or a recovery key and says to keep it somewhere safe, here’s where to put it, how many copies to keep, and how Slinky crosses codes off as you use them.
lede: Turning on two-step sign-in usually ends with a list of codes and the words “store these somewhere safe.” Here’s what that can mean in practice.
faq:
  - ["Should backup codes go in the same place as the password?", "It’s a trade-off. Keeping them apart means one leak doesn’t give away both. Keeping them together means one lost vault loses both. Many people keep the password in Apple Passwords and the codes somewhere else, plus a printed copy of the most important ones."]
  - ["What happens when I use a backup code?", "Each code usually works once. Slinky crosses a code off when you copy it, and warns you when only a few are left so you can make a new set on the website."]
  - ["Does Slinky store crypto wallet recovery phrases?", "No. If you paste something that looks like a wallet recovery phrase, Slinky says so and doesn’t save it. Those belong on paper or a hardware wallet."]
---

## What you’re being given

- **Backup codes** (also called recovery codes): usually 8 to 16 short codes. Each one signs you in once if you lose your phone or authenticator app.
- **A recovery key**: one long key that gets you back into an account, such as an Apple Account recovery key or a password manager’s emergency kit.

Either one can get someone into your account, so treat it like a password. And you’ll need it on the day you’ve lost the device that normally signs you in, so don’t keep the only copy on that device.

## Good places, and what to avoid

- **Printed and put away.** Simple, and nothing online can reach it. Good for the few accounts you can’t lose: your email, your Apple Account, your password manager.
- **An encrypted app on a computer you use**, so the codes are there when your phone isn’t.
- **Avoid:** a screenshot in your photo library, a note that syncs everywhere, an email to yourself, or a text file in Downloads called `backup-codes.txt`.

Whatever you choose, write down which account the codes belong to and the date you made them. Old codes stop working when you make a new set.

## How Slinky does it

[Slinky](/) has a place called Recovery, just for these:

- **Paste the whole list.** Slinky recognises a set of backup codes and saves them as one item for that account.
- **Codes cross themselves off.** Copying a code marks it used, since each code works once. When only a few are left, Slinky says so: “Only 3 codes left. Consider generating new ones.”
- **Recovery keys get a reminder** to keep a printed copy, until you print one or mark that you have it somewhere else.
- **Encrypted, with a backup you hold.** Everything is in one encrypted file on your Mac, opened with Touch ID. Your own Slinky Recovery Key (print it, or keep it in Apple Passwords) opens it on a new Mac.
- **Quick Access (⌥⌘K)** finds a code from any app when a website asks for one. Copies are kept out of clipboard history and cleared after 60 seconds.
