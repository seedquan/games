import { build } from 'esbuild';
import { readFile, writeFile } from 'node:fs/promises';

const result = await build({
  entryPoints: ['src/app.mjs'],
  bundle: true,
  minify: true,
  format: 'iife',
  target: 'es2022',
  write: false,
  legalComments: 'inline',
});
const template = await readFile('src/template.html', 'utf8');
const css = await readFile('src/style.css', 'utf8');
const license = await readFile('node_modules/three/LICENSE', 'utf8');
const html = template
  .replace('/* APP_STYLE */', css)
  .replace('/* APP_SCRIPT */', () => result.outputFiles[0].text.replace(/<\/script/gi, '<\\/script'))
  .replace('<!-- THIRD_PARTY_LICENSE -->', () => `<!-- Three.js license:\n${license}\n-->`);
await writeFile('index.html', html);
console.log(`Built standalone terrarium/index.html (${Math.round(html.length / 1024)} KB)`);
