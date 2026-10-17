// Cloudflare Pages Function for "/": serve homepage.md to clients that ask for Markdown
// (Accept: text/markdown), the same as the family's Netlify edge function. Everyone else gets the page.
interface Env { ASSETS: { fetch: (req: Request | string) => Promise<Response> } }

function prefersMarkdown(accept: string | null): boolean {
  if (!accept) return false;
  const types = accept.split(',').map((part) => {
    const [type, ...params] = part.trim().split(';');
    const q = params.map((p) => p.trim()).find((p) => p.startsWith('q='));
    return { type: type.trim().toLowerCase(), q: q ? Number(q.slice(2)) : 1 };
  });
  const md = types.find((t) => t.type === 'text/markdown');
  const html = types.find((t) => t.type === 'text/html');
  return !!md && md.q > 0 && (!html || md.q >= html.q);
}

export const onRequestGet = async (context: { request: Request; env: Env; next: () => Promise<Response> }) => {
  if (!prefersMarkdown(context.request.headers.get('accept'))) return context.next();
  const res = await context.env.ASSETS.fetch(new URL('/homepage.md', context.request.url).toString());
  if (!res.ok) return context.next();
  const text = await res.text();
  return new Response(text, {
    headers: {
      'content-type': 'text/markdown; charset=utf-8',
      'x-markdown-tokens': String(Math.max(1, Math.round(text.length / 4))),
      'cache-control': 'public, max-age=300',
      vary: 'Accept',
    },
  });
};
