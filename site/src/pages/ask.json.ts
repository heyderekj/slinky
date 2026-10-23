// What Spotlight's answers are grounded in: the FAQ (with anchors, for source links) and how to sound.
// Read by functions/api/ask.ts together with /homepage.md and /llms.txt. Same shape on all three sites.
import { faq, faqId } from '../data/faq';
import { compareText, mark } from '../data/compare';
import { competitors } from '../data/competitors';
import release from '../release.json';

/** One comparison as plain sentences: who each is for, then the table. */
const said = (v: string) => { const m = mark(v); return m.cls === 'text' ? v : `${m.label.toLowerCase()}${m.note ? ` (${m.note})` : ''}`; };
const themText = (c: (typeof competitors)[number]) =>
  [`Choose ${c.name} if: ${c.chooseThem.join(' ')}`, `Choose Slinky if: ${c.chooseSlinky.join(' ')}`, ...c.rows.map(([row, us, them]) => `${row}: Slinky ${said(us)}; ${c.name} ${said(them)}.`), 'As of October 2026.'].join('\n');

export const GET = () =>
  new Response(
    JSON.stringify({
      app: 'Slinky',
      line: 'Slinky keeps secrets out of files.',
      version: release.version,
      download: release.dmg,
      email: 'derek@testamentmade.com',
      voice:
        'Plain, calm and serious about security; never overclaim what Slinky protects against. A dry, light touch is fine only when the question itself is silly.',
      faq: faq.map(([q, a]) => ({ id: faqId(q), q, a })),
      compare: [
        { name: 'Slinky compared with Apple Passwords, 1Password, .env files, Doppler or Infisical, and Keychain Access', url: '/#compare', text: compareText() },
        ...competitors.map((c) => ({ name: `Slinky vs ${c.name}`, url: `/compare/${c.slug}/`, text: themText(c) })),
      ],
    }),
    { headers: { 'content-type': 'application/json; charset=utf-8' } },
  );
