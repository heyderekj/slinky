// The comparison table on the homepage. Also read by ask.json, so Spotlight's answers can compare too.
// Each cell: 'yes', 'no' or 'part', with an optional ':short note', or plain text.
export const compare = {
  cols: ['Slinky', 'Apple Passwords', '1Password', '.env files', 'Doppler or Infisical', 'Keychain Access'],
  rows: [
    ['Made for API keys and tokens', ['yes', 'no', 'yes', 'part:Plain text', 'yes', 'part:Generic items']],
    ['A project’s .env, per environment', ['yes', 'no', 'part:With its CLI', 'yes', 'yes', 'no']],
    ['A command that runs your app', ['yes', 'no', 'yes:op run', 'no', 'yes', 'part:Prints values']],
    ['AI agents use keys without seeing them', ['yes', 'no', 'part:With its CLI', 'no:In the clear', 'part:With its CLI', 'no']],
    ['Recovery codes that cross themselves off', ['yes', 'no', 'no', 'no', 'no', 'no']],
    ['Stays on your Mac', ['yes', 'part:iCloud', 'no:Their cloud', 'part:Unencrypted', 'no:Their servers', 'yes']],
    ['Opens with Touch ID', ['yes', 'yes', 'yes', 'no', 'no', 'part:Password']],
    ['Price', ['Free, open source', 'Free', 'Subscription', 'Free', 'Free tier, then paid', 'Free']],
  ] as [string, string[]][],
};

/** The table as plain sentences, for the answers. */
export const compareText = () =>
  compare.rows
    .map(([row, cells]) =>
      `${row}: ` +
      cells
        .map((v, i) => {
          const [kind, note] = v.includes(':') ? v.split(':') : [v, ''];
          const said = kind === 'yes' ? 'yes' : kind === 'no' ? 'no' : kind === 'part' ? 'partly' : v;
          return `${compare.cols[i]} ${said}${note && said !== v ? ` (${note})` : ''}`;
        })
        .join('; ') + '.',
    )
    .join('\n') + '\nAs of October 2026.';
