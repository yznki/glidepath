import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// GitHub Pages project site: https://yznki.github.io/glidepath/
export default defineConfig({
  site: 'https://yznki.github.io',
  base: '/glidepath',
  output: 'static',
  integrations: [sitemap()],
  build: { inlineStylesheets: 'auto' },
});
