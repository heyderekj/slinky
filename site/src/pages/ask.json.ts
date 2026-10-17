// What Spotlight's answers are grounded in: the FAQ (with anchors, for source links) and how to sound.
// Read by functions/api/ask.ts together with /homepage.md and /llms.txt. Same shape on all three sites.
import { faq, faqId } from '../data/faq';
import release from '../release.json';

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
    }),
    { headers: { 'content-type': 'application/json; charset=utf-8' } },
  );
