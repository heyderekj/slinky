// @ts-check
import { defineConfig } from 'astro/config';

// Same setup as testamentmade.com: a static Astro site on Cloudflare Pages (root `site`, build `npm run build`, output `dist`).
export default defineConfig({
  site: 'https://slinkyfiles.com',
  output: 'static',
  build: { format: 'directory' },
  devToolbar: { enabled: false },
});
