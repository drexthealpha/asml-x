import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

// Tailwind v4 is a Vite PLUGIN, not a PostCSS config. v3's tailwind.config.js plus
// postcss.config.js is gone; configuration is CSS-first via @theme in index.css.
export default defineConfig({
  plugins: [react(), tailwindcss()],
  build: { outDir: "dist", sourcemap: false },
});
