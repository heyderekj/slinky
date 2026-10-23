// The sitemap, built from the same lists as the pages, so a new comparison or guide is never left out.
import { competitors } from '../data/competitors';
import { guides } from '../data/guides';

const site = 'https://slinkyfiles.com';
const pages: [string, string, string][] = [
  ['/', 'weekly', '1.0'],
  ['/compare/', 'monthly', '0.85'],
  ...competitors.map((c): [string, string, string] => [`/compare/${c.slug}/`, 'monthly', '0.75']),
  ['/guides/', 'monthly', '0.8'],
  ...guides.map((g): [string, string, string] => [`/guides/${g.slug}/`, 'monthly', '0.7']),
];

export const GET = () =>
  new Response(
    `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n` +
      pages.map(([path, freq, pri]) => `  <url><loc>${site}${path}</loc><changefreq>${freq}</changefreq><priority>${pri}</priority></url>`).join('\n') +
      `\n</urlset>\n`,
    { headers: { 'content-type': 'application/xml; charset=utf-8' } },
  );
