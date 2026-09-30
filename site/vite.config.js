import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

export default defineConfig({
  plugins: [svelte()],
  // Relative paths: Pages serves the site under /<repository name>/.
  base: './',
  // The fonts and logo come from the app's assets/.
  server: { fs: { allow: ['..'] } },
});
