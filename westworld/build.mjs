import { readFile, writeFile } from 'node:fs/promises';
import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';

const root = new URL('./', import.meta.url);
const css = await readFile(new URL('src/style.css', root), 'utf8');
const template = await readFile(new URL('src/template.html', root), 'utf8');
for (const marker of ['/* APP_STYLE */', '/* APP_SCRIPT */', '<!-- THIRD_PARTY_LICENSE -->']) {
  if (!template.includes(marker)) throw new Error(`Missing build marker: ${marker}`);
}
const result = await build({
  absWorkingDir: fileURLToPath(root), entryPoints: ['src/app.mjs'],
  bundle: true, minify: true, format: 'iife', target: 'es2022', write: false, legalComments: 'inline',
});
const script = result.outputFiles[0].text;
const license = await readFile(new URL('node_modules/three/LICENSE', root), 'utf8');
const html = template.replace('/* APP_STYLE */', () => css)
  .replace('/* APP_SCRIPT */', () => script.replace(/<\/script/gi, '<\\/script'))
  .replace('<!-- THIRD_PARTY_LICENSE -->', () => `<!-- Three.js license:\n${license}\n-->`);
await writeFile(new URL('index.html', root), html);
console.log(`Built self-contained westworld/index.html (${Math.round(Buffer.byteLength(html) / 1024)} KB).`);
