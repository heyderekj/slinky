// The compare pages (/compare/<slug>/), the hub, the sitemap and llms.txt. Checked against each tool's own
// pricing and docs on 2026-10-23; the pages say "As of October 2026". Cells use compare.ts's format: 'yes',
// 'no' or 'part', with an optional ':short note' (no colons in the note), or plain text.
// Sources:
//   1Password: 1password.com/pricing/password-manager, 1password.dev/environments (and /mcp-server), 1password.dev/cli
//   Apple Passwords: support.apple.com/guide/passwords
//   Keychain Access: support.apple.com/guide/keychain-access, `security find-generic-password -h` on macOS 26
//   .env: blog.gitguardian.com/the-state-of-secrets-sprawl-2026
//   Doppler: doppler.com/pricing, docs.doppler.com/docs/automatic-fallbacks, docs.doppler.com/docs/mcp
//   Infisical: infisical.com/pricing, github.com/Infisical/infisical, infisical.com/docs/cli/commands/run, Agent Vault post (Apr 2026)
//   Bitwarden: bitwarden.com/pricing, bitwarden.com/help/secrets-manager-cli, github.com/bitwarden/sdk-sm, bitwarden.com/blog/bitwarden-mcp-server
//   Vault: github.com/hashicorp/vault LICENSE (BSL 1.1), developer.hashicorp.com/vault/docs/mcp-server, openbao.org
//   dotenvx: dotenvx.com, dotenvx.com/agents, github.com/dotenvx/dotenvx
//   direnv: direnv.net

export const groups = {
  password: 'Password managers',
  hosted: 'Secret managers for teams',
  files: 'Files and built-in tools',
} as const;

export interface Competitor {
  slug: string;
  name: string;
  /** Where the facts came from, shown under the table. */
  site: string;
  url: string;
  group: keyof typeof groups;
  /** The <title>. */
  seo: string;
  description: string;
  /** One line for link cards. */
  blurb: string;
  /** The lede. May hold a link. */
  intro: string;
  chooseThem: string[];
  chooseSlinky: string[];
  rows: [string, string, string][];
  faq: [string, string][];
  get?: { title: string; text: string };
  /** A plain glyph tile for things without a logo of their own (a file, the keychain). Otherwise the logo or monogram. */
  glyph?: string;
  /** The app's own icon (an image in /public/icons), for a tool that is an app on this Mac. */
  icon?: string;
}

const SLINKY = {
  keys: 'yes',
  env: 'yes',
  run: 'yes:slinky run',
  agents: 'yes',
  codes: 'yes',
  where: 'An encrypted file on your Mac',
  noAccount: 'yes',
  share: 'yes:Encrypted files, no server',
  touchid: 'yes',
  open: 'yes:MIT',
  price: 'Free',
  runs: 'Mac, Apple silicon',
};

const L = {
  keys: 'Made for API keys and tokens',
  env: 'A project’s .env, per environment',
  run: 'Starts your app with its variables',
  agents: 'AI agents see names, not values',
  codes: 'Backup codes that cross themselves off',
  where: 'Where your secrets are kept',
  noAccount: 'Works without an account',
  share: 'Share with your team',
  touchid: 'Opens with Touch ID',
  open: 'Open source',
  price: 'Price',
  runs: 'Runs on',
};

type Them = Partial<Record<keyof typeof L, string>>;
/** Rows in the same order on every page; leave a key out to skip the row. */
const rows = (them: Them): [string, string, string][] =>
  (Object.keys(L) as (keyof typeof L)[]).filter((k) => them[k] !== undefined).map((k) => [L[k], SLINKY[k], them[k]!]);

export const competitors: Competitor[] = [
  {
    slug: '1password',
    icon: '/icons/1password-160.webp',
    name: '1Password',
    site: '1password.com',
    url: 'https://1password.com/pricing/password-manager',
    group: 'password',
    seo: 'Slinky vs 1Password for API keys and .env variables',
    description: '1Password is a full password manager with developer tools. Slinky is a free, open-source Mac app just for API keys, .env variables and backup codes, with no account.',
    blurb: 'A full password manager with developer tools, or a free Mac app just for keys.',
    intro: '<a href="https://1password.com" rel="noopener">1Password</a> is a password manager for every device, and its developer tools are good: <code>op run</code>, Environments for a project’s variables, an SSH agent, and an MCP server that shows agents names only. Slinky does less, on purpose: it’s only for keys, .env variables and backup codes, on your Mac, with no account.',
    chooseThem: [
      'You want passwords, passkeys and keys in one app.',
      'You also use Windows, Linux, or need everything on your phone.',
      'Your team shares vaults and needs admin controls.',
      'You already pay for 1Password and its developer tools fit how you work.',
    ],
    chooseSlinky: [
      'You keep passwords in Apple Passwords and want keys somewhere separate.',
      'You’d rather have no account and no cloud: one encrypted file on your Mac.',
      'You want backup codes that cross themselves off as you use them.',
      'You want to find copies of your keys in git history, AI conversations and shell history.',
      'You want it free and open source.',
    ],
    rows: rows({
      keys: 'yes',
      env: 'yes:Environments',
      run: 'yes:op run',
      agents: 'yes:Environments MCP',
      codes: 'no',
      where: 'Their cloud, synced to each device',
      noAccount: 'no',
      share: 'yes:Shared vaults',
      touchid: 'yes',
      open: 'no',
      price: '$47.88 a year (Individual)',
      runs: 'Mac, Windows, Linux, iPhone, Android, web',
    }),
    faq: [
      ['Can I move my keys from 1Password to Slinky?', 'Yes. Export a .1pux file from 1Password and import it into Slinky. Slinky picks out API keys, tokens, backup codes and recovery keys, including keys in notes, and leaves website passwords behind. You choose what comes in, and Undo takes the import back.'],
      ['Can I use both?', 'Yes. Many people keep passwords in a password manager and keys in Slinky. Slinky doesn’t read or change 1Password.'],
      ['Does 1Password keep values away from AI agents too?', 'Yes. 1Password’s Environments MCP server, from May 2026, shows agents variable names and gives values only to a process you approve. Slinky works the same way, on your Mac and without an account: agents run commands through slinky run, and you approve each one with Touch ID.'],
    ],
  },
  {
    slug: 'apple-passwords',
    icon: '/icons/apple-passwords-160.webp',
    name: 'Apple Passwords',
    site: 'support.apple.com',
    url: 'https://support.apple.com/guide/passwords/welcome/mac',
    group: 'password',
    seo: 'Slinky vs Apple Passwords for API keys and backup codes',
    description: 'Apple Passwords is the right place for website passwords and passkeys. Slinky is for the other things: API keys, a project’s .env variables, and two-factor backup codes.',
    blurb: 'Use Apple Passwords for sign-ins, and Slinky for keys and backup codes.',
    intro: '<a href="https://support.apple.com/guide/passwords/welcome/mac" rel="noopener">Apple Passwords</a> is built into your Mac and it’s great for logins: passwords, passkeys, verification codes and Wi-Fi. Slinky isn’t a replacement. It’s for the things Passwords has no place for: API keys, each project’s .env, and the backup codes websites tell you to keep somewhere safe.',
    chooseThem: [
      'It’s a website password or a passkey.',
      'You want verification codes filled in when you sign in.',
      'You want it on your iPhone and iPad, synced with iCloud.',
      'You share passwords with family in a shared group.',
    ],
    chooseSlinky: [
      'It’s an API key or token your software or AI tools use.',
      'It’s a project’s .env variables, for Local, Preview and Production.',
      'It’s a list of backup codes or a recovery key.',
      'You want to start your app with its keys, without a .env file on disk.',
    ],
    rows: rows({
      keys: 'part:In a password’s notes',
      env: 'no',
      run: 'no',
      agents: 'no',
      codes: 'no',
      where: 'Your Mac, synced with iCloud Keychain',
      noAccount: 'part:Apple Account to sync',
      share: 'part:Passwords only',
      touchid: 'yes',
      open: 'no',
      price: 'Free with macOS',
      runs: 'Apple devices, iCloud for Windows',
    }),
    faq: [
      ['Should I keep passwords in Slinky?', 'No. Website passwords belong in Apple Passwords. Slinky is for the other things: API keys, tokens, .env variables, backup codes and recovery keys.'],
      ['Can Slinky import from Apple Passwords?', 'Yes. Export a CSV from Apple Passwords and import it into Slinky. Slinky picks out keys, tokens and codes, even ones kept in notes, and skips the passwords. Export files aren’t encrypted, so Slinky can put the file in the Trash once the import is saved.'],
      ['Where should my Slinky Recovery Key go?', 'Print it, or keep it in Apple Passwords. It opens your Slinky vault on another Mac, or if Touch ID stops working.'],
    ],
  },
  {
    slug: 'bitwarden',
    icon: '/icons/bitwarden-160.webp',
    name: 'Bitwarden',
    site: 'bitwarden.com',
    url: 'https://bitwarden.com/pricing/',
    group: 'password',
    seo: 'Slinky vs Bitwarden and Bitwarden Secrets Manager',
    description: 'Bitwarden is an open-source password manager with a separate Secrets Manager for teams. Slinky is a free, open-source Mac app for API keys, .env variables and backup codes, with no account.',
    blurb: 'An open-source password manager and a Secrets Manager for teams, or one Mac app.',
    intro: '<a href="https://bitwarden.com" rel="noopener">Bitwarden</a> is an open-source password manager you can use on any device or host yourself. For keys, it has a separate product, Bitwarden Secrets Manager, with projects, machine accounts and <code>bws run</code>. Slinky keeps keys, .env variables and backup codes in one Mac app, with no account or server.',
    chooseThem: [
      'You want an open-source password manager on every device.',
      'You want to host it yourself.',
      'Your team needs machine accounts for CI and servers (Secrets Manager).',
      'You need Windows or Linux.',
    ],
    chooseSlinky: [
      'You want keys, .env variables and backup codes in one place, without a second product.',
      'You’d rather have no account and no server.',
      'You want AI agents to see names only.',
      'You want backup codes that cross themselves off.',
    ],
    rows: rows({
      keys: 'part:In Secrets Manager',
      env: 'part:Projects in Secrets Manager',
      run: 'yes:bws run',
      agents: 'no:Its MCP server can return values',
      codes: 'no',
      where: 'Their cloud, or your own server',
      noAccount: 'no',
      share: 'yes:Organizations',
      touchid: 'yes',
      open: 'part:Password Manager',
      price: 'Premium $19.80 a year. Secrets Manager free for 2 people',
      runs: 'Mac, Windows, Linux, phones, web',
    }),
    faq: [
      ['Is Bitwarden Secrets Manager open source?', 'Bitwarden’s password manager apps are open source (GPL and AGPL). The bws command and SDK that Secrets Manager uses are under Bitwarden’s own SDK license, so it’s better described as source-available.'],
      ['Can I import from Bitwarden?', 'Yes. Export a CSV from Bitwarden, custom fields included, and import it into Slinky. Slinky picks out keys, tokens and codes and leaves passwords behind.'],
    ],
  },
  {
    slug: 'doppler',
    icon: '/icons/doppler-160.webp',
    name: 'Doppler',
    site: 'doppler.com',
    url: 'https://www.doppler.com/pricing',
    group: 'hosted',
    seo: 'Slinky vs Doppler: a Mac app or hosted secrets',
    description: 'Doppler is a hosted secrets manager that syncs variables to your team, CI and hosts. Slinky keeps your keys and .env variables in an encrypted file on your Mac, free and open source, and shares them through encrypted files instead of a server.',
    blurb: 'A hosted secrets manager for teams, or keys that stay on your Mac.',
    intro: '<a href="https://www.doppler.com" rel="noopener">Doppler</a> keeps a team’s secrets on its servers and syncs them to everyone’s machines, CI and cloud hosts, with access controls and logs. Slinky keeps keys on your Mac and shares them with the people you choose, through encrypted files, with nothing on a server.',
    chooseThem: [
      'Several people need the same secrets, with roles and access logs.',
      'Secrets need to sync to CI and cloud hosts automatically.',
      'You want one source of truth across many machines and servers.',
    ],
    chooseSlinky: [
      'It’s your own keys, on your own Mac.',
      'You’d rather your secrets weren’t on anyone’s server.',
      'You also want somewhere for backup codes and recovery keys.',
      'You want AI agents to see names only, with Touch ID for each command.',
      'Your small team can share a project through a folder you already sync.',
    ],
    rows: rows({
      keys: 'yes',
      env: 'yes',
      run: 'yes:doppler run',
      agents: 'no:Its MCP server can read values',
      codes: 'no',
      where: 'Their cloud, with an encrypted copy on each machine',
      noAccount: 'no',
      share: 'yes',
      touchid: 'no',
      open: 'part:The CLI',
      price: 'Free for small teams, then $21 a person a month',
      runs: 'Any computer, through its CLI and website',
    }),
    faq: [
      ['Can Slinky send my variables to a host the way Doppler does?', 'Partly. Share › Send to Host sends a project’s variables to Vercel, Netlify, Cloudflare or Fly.io through their own command-line tools, signed in as you, after you see the names and confirm with Touch ID. It runs when you choose, not on its own.'],
      ['Does Slinky work for a team?', 'Yes, without a server. Share with… sends items as an encrypted file only the people you pick can open, and a shared project keeps one signed, encrypted file in a folder your team already syncs. There are no roles, audit logs or syncing to CI, which is where Doppler is the better fit.'],
    ],
  },
  {
    slug: 'infisical',
    icon: '/icons/infisical-160.webp',
    name: 'Infisical',
    site: 'infisical.com',
    url: 'https://infisical.com/pricing',
    group: 'hosted',
    seo: 'Slinky vs Infisical: a Mac app or a secrets platform',
    description: 'Infisical is an open-source secrets platform you can use in its cloud or host yourself. Slinky is a free, open-source Mac app that keeps keys and .env variables in an encrypted file on your Mac.',
    blurb: 'An open-source secrets platform you host, or a Mac app with no server.',
    intro: '<a href="https://infisical.com" rel="noopener">Infisical</a> is an open-source secrets platform for teams: projects and environments, machine identities, secret rotation, and <code>infisical run</code>, in its cloud or on your own server. Slinky is a Mac app for your own keys, with no server to run.',
    chooseThem: [
      'Your team needs shared secrets, roles and audit logs.',
      'You want to self-host and control the server.',
      'You need machine identities for CI, servers and Kubernetes.',
    ],
    chooseSlinky: [
      'It’s your own keys, and you don’t want to run or sign up for a server.',
      'You want Touch ID before any command gets your keys.',
      'You also keep backup codes and recovery keys.',
      'You want AI agents to see names only, today, without an experimental proxy.',
      'Your small team can share keys through encrypted files, with no server to run.',
    ],
    rows: rows({
      keys: 'yes',
      env: 'yes',
      run: 'yes:infisical run',
      agents: 'part:Agent Vault, experimental',
      codes: 'no',
      where: 'Their cloud, or your own server',
      noAccount: 'no',
      share: 'yes',
      touchid: 'no',
      open: 'yes:MIT core',
      price: 'Free for 5 identities, then $20 each a month',
      runs: 'Any computer, through its CLI and website',
    }),
    faq: [
      ['What is Infisical’s Agent Vault?', 'An open-source proxy, from April 2026, that adds credentials to an agent’s requests on the way out so the agent never holds them. Infisical labels it experimental and not yet for production.'],
      ['Can I self-host Slinky?', 'There’s nothing to host. Slinky is an app on your Mac and your vault is a file. If you turn on sync, an encrypted copy goes in a folder you choose, and your own sync service moves it.'],
    ],
  },
  {
    slug: 'hashicorp-vault',
    name: 'HashiCorp Vault',
    site: 'developer.hashicorp.com',
    url: 'https://developer.hashicorp.com/vault',
    group: 'hosted',
    seo: 'Slinky vs HashiCorp Vault for your own keys',
    description: 'HashiCorp Vault is server infrastructure for an organisation’s secrets. Slinky is a free Mac app for one developer’s API keys, .env variables and backup codes.',
    blurb: 'Secrets infrastructure for organisations, or a Mac app for your own keys.',
    intro: '<a href="https://developer.hashicorp.com/vault" rel="noopener">HashiCorp Vault</a> is infrastructure: a server for an organisation’s secrets, with dynamic database credentials, certificates and many ways to sign in. It’s more than most people need for their own keys. Slinky is an app, not a server.',
    chooseThem: [
      'You run infrastructure that needs dynamic credentials, certificates or encryption as a service.',
      'You have people to run and secure a Vault cluster, or you pay for HCP Vault.',
      'Many services and machines need secrets with detailed policies.',
    ],
    chooseSlinky: [
      'You want your own keys safe on your Mac today, with nothing to run.',
      'You want your app started with its variables after Touch ID.',
      'You also keep backup codes and recovery keys.',
    ],
    rows: rows({
      keys: 'yes',
      env: 'part:Paths you set up',
      run: 'part:With Vault Agent or envconsul',
      agents: 'no:Its MCP server can return secrets',
      codes: 'no',
      where: 'Your servers, or HCP',
      noAccount: 'no',
      share: 'yes:With policies',
      touchid: 'no',
      open: 'part:Source-available (BSL)',
      price: 'Community edition free. HCP Vault paid by use',
      runs: 'Servers, on any system',
    }),
    faq: [
      ['Is Vault open source?', 'Since version 1.15 (2023), Vault is under the Business Source License, now from IBM. OpenBao is a fork under the open-source MPL 2.0, run by the Linux Foundation.'],
      ['What about Vault’s dev mode on my laptop?', 'vault server -dev keeps everything in memory and starts unsealed with a root token. HashiCorp says never to run it in production, and everything is gone when it stops.'],
    ],
  },
  {
    slug: 'env-files',
    glyph: 'file',
    name: '.env files',
    site: 'blog.gitguardian.com',
    url: 'https://blog.gitguardian.com/the-state-of-secrets-sprawl-2026/',
    group: 'files',
    seo: 'Slinky vs .env files: keep keys out of the folder',
    description: 'A .env file keeps a project’s keys in plain text in the project folder. Slinky keeps the same variables encrypted on your Mac and starts your app with them, with no file on disk.',
    blurb: 'Plain text in the project folder, or encrypted and out of it.',
    intro: 'A <code>.env</code> file is how most frameworks expect variables, and it’s simple. It’s also plain text in the project folder, one forgotten line in <code>.gitignore</code> away from the repository, and readable by any tool that looks around the project, AI agents included. GitGuardian counted 28.65 million new secrets in public GitHub commits in 2025.',
    chooseThem: [
      'The values aren’t secret, like a public URL or a feature flag.',
      'It’s a throwaway project with test keys only.',
      'Your host or framework needs a real file and nothing else will do.',
    ],
    chooseSlinky: [
      'The values are real keys, especially live ones.',
      'You use AI coding tools that can read the project folder.',
      'You have several environments and want to see them side by side.',
      'You want a .env.example with names only, kept up to date.',
    ],
    rows: rows({
      keys: 'part:Plain text',
      env: 'yes',
      run: 'part:With a dotenv library',
      agents: 'no:Agents can read the file',
      codes: 'no',
      where: 'Plain text in the project folder',
      noAccount: 'yes',
      share: 'no:Pasted in chat',
      touchid: 'no',
      price: 'Free',
    }),
    faq: [
      ['Do I have to change my app to use Slinky?', 'No. Your app still reads environment variables. Instead of a .env file, slinky run -- npm run dev starts it with the same variables after Touch ID. Or copy an environment as .env lines when a host’s dashboard asks for them.'],
      ['Can Slinky take my existing .env files?', 'Yes. Drop the project folder on Slinky. It reads the .env files (read-only), apps inside the folder too, and shows each environment. Move into Slinky saves the variables, writes a names-only .env.example and puts the .env in the Trash, when you choose it.'],
    ],
    get: { title: 'Take the keys out of the folder.', text: 'Free, open source, and your app still gets its variables.' },
  },
  {
    slug: 'dotenvx',
    icon: '/icons/dotenvx-160.webp',
    name: 'dotenvx',
    site: 'dotenvx.com',
    url: 'https://dotenvx.com',
    group: 'files',
    seo: 'Slinky vs dotenvx: encrypted .env or a Mac vault',
    description: 'dotenvx encrypts the values in a .env file so it can be committed. Slinky keeps the variables in an encrypted vault on your Mac instead. You can also use them together.',
    blurb: 'An encrypted .env you commit, or variables kept out of the repo.',
    intro: '<a href="https://dotenvx.com" rel="noopener">dotenvx</a>, from the author of dotenv, encrypts each value in a <code>.env</code> file so the file can live in your repository. The private key that opens it still has to live somewhere. Slinky keeps variables out of the repository altogether, and can also hold that private key.',
    chooseThem: [
      'You want encrypted variables to travel with the repository, to every machine and CI.',
      'You work on Linux or Windows too.',
      'Your team already shares one private key per environment.',
    ],
    chooseSlinky: [
      'You’d rather nothing secret was in the repository, even encrypted.',
      'You want Touch ID before a command gets your keys.',
      'You want AI agents to see names only.',
      'You also keep backup codes and recovery keys.',
    ],
    rows: rows({
      keys: 'yes',
      env: 'yes',
      run: 'yes:dotenvx run',
      agents: 'part:Hides values in logs',
      codes: 'no',
      where: 'An encrypted .env, with the key kept separately',
      noAccount: 'yes',
      share: 'part:One private key per environment',
      touchid: 'no',
      open: 'yes:BSD-3',
      price: 'Free, with paid plans for teams',
      runs: 'Any computer',
    }),
    faq: [
      ['Can I use dotenvx and Slinky together?', 'Yes. Keep DOTENV_PRIVATE_KEY in Slinky instead of a .env.keys file, and run slinky run --key DOTENV_PRIVATE_KEY -- dotenvx run -- npm start. Touch ID unlocks the key for that one command.'],
      ['Does dotenvx keep values from AI agents?', 'It hides values in output, so logs show [REDACTED], but a process it starts still gets the real values. Slinky’s agents see names only and need your Touch ID for each command; live keys are held back.'],
    ],
  },
  {
    slug: 'direnv',
    icon: '/icons/direnv-160.webp',
    name: 'direnv',
    site: 'direnv.net',
    url: 'https://direnv.net',
    group: 'files',
    seo: 'Slinky vs direnv: variables that load when you cd',
    description: 'direnv loads a folder’s .envrc when you cd into it. Slinky can load a project’s variables the same way, from an encrypted vault instead of a plain-text file.',
    blurb: 'Variables that load when you cd, from a plain file or an encrypted vault.',
    intro: '<a href="https://direnv.net" rel="noopener">direnv</a> loads a folder’s <code>.envrc</code> when you <code>cd</code> into it and unloads it when you leave. It’s fast and works in many shells, but it doesn’t encrypt anything: the <code>.envrc</code> is a plain-text script, unless it calls a secret manager.',
    chooseThem: [
      'You set far more than secrets per folder: paths, tool versions, layouts.',
      'You use a shell Slinky’s hook doesn’t cover.',
      'Your values aren’t secret.',
    ],
    chooseSlinky: [
      'The values are real keys and you don’t want them in a file.',
      'You want to approve with Touch ID before your keys load.',
      'You want AI agents to see names only.',
    ],
    rows: rows({
      keys: 'no',
      env: 'part:One .envrc per folder',
      run: 'part:Loads when you cd',
      agents: 'no:Any shell there gets them',
      codes: 'no',
      where: 'Plain text in .envrc',
      noAccount: 'yes',
      share: 'no',
      touchid: 'no',
      open: 'yes:MIT',
      price: 'Free',
      runs: 'Mac and Linux, many shells',
    }),
    faq: [
      ['Does Slinky load variables when I cd?', 'Yes, if you turn it on. slinky hook zsh (or bash or fish) adds shell code that loads a linked project’s variables when you cd into it and unloads them when you leave.'],
      ['Can I keep direnv and get the values from Slinky?', 'Yes. In .envrc, use eval "$(slinky env --export)". Slinky asks before printing the export lines, and the .envrc itself holds no values.'],
    ],
  },
  {
    slug: 'keychain-access',
    icon: '/icons/keychain-access-160.webp',
    name: 'Keychain Access',
    site: 'support.apple.com',
    url: 'https://support.apple.com/guide/keychain-access/welcome/mac',
    group: 'files',
    seo: 'Slinky vs Keychain Access for API keys on a Mac',
    description: 'Keychain Access can hold a key as a generic password, and the security command can read it back. Slinky is made for keys: projects, environments, Touch ID, and no values printed to your terminal.',
    blurb: 'The Mac’s built-in keychain, or an app made for keys.',
    intro: '<a href="https://support.apple.com/guide/keychain-access/welcome/mac" rel="noopener">Keychain Access</a> is still on every Mac (since Sequoia it’s in /System/Library/CoreServices/Applications), now mostly for certificates and app passwords. You can save a key as a generic password and read it back with <code>security find-generic-password -w</code>. It works, but it wasn’t made for keys.',
    chooseThem: [
      'It’s a certificate or a password an app saves for itself.',
      'You need one value in a script and don’t mind it printing.',
      'You don’t want to install anything.',
    ],
    chooseSlinky: [
      'You have more than a handful of keys, across projects and environments.',
      'You want to start your app with its keys, without printing them in your terminal.',
      'You want to see where a key is used, and when it was last used.',
      'You also keep backup codes and recovery keys.',
    ],
    rows: rows({
      keys: 'part:Generic passwords',
      env: 'no',
      run: 'part:Prints values',
      agents: 'no',
      codes: 'no',
      where: 'Your Mac (login keychain)',
      noAccount: 'yes',
      share: 'no',
      touchid: 'part:Your Mac’s password',
      open: 'no',
      price: 'Free with macOS',
      runs: 'Mac',
    }),
    faq: [
      ['Does Slinky use the keychain?', 'Slinky keeps everything in its own encrypted file. Your Mac’s Secure Enclave protects the key that opens it, and Touch ID unlocks it. Slinky never uses the security command.'],
      ['What’s wrong with security find-generic-password -w?', 'Nothing, for one value. But it prints the value, so it ends up in your terminal, and anything you pipe it into. Used in an export line, it can land in your shell history.'],
    ],
  },
];
