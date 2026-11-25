// Copies runtime assets from node_modules into www/vendor so the app works offline inside the native shell.
import { cpSync, mkdirSync, existsSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
const out = 'www/vendor';
mkdirSync(out, { recursive: true });
const font = 'node_modules/@fontsource-variable/readex-pro/files/';
for (const f of ['readex-pro-arabic-wght-normal.woff2', 'readex-pro-latin-wght-normal.woff2']) cpSync(font + f, `${out}/${f}`);
cpSync('node_modules/@supabase/supabase-js/dist/umd/supabase.js', `${out}/supabase.js`);
// The Thmanyah typeface is licensed: its files never go into the repository, and the licence only allows embedding it
// as part of a packaged product, not as loose font files. So it is folded into one stylesheet as inline data.
// Locally the files sit in designs/fonts; in CI they are unpacked there from the encrypted bundle.
// Without them the stylesheet is empty and the app falls back to Readex Pro.
const thm = 'designs/fonts/';
const faces = [['Regular', 400], ['Medium', 500], ['Bold', 700]].filter(([w]) => existsSync(`${thm}thmanyahsans-${w}.woff2`)).map(([w, n]) =>
  `@font-face{font-family:"Thmanyah Sans";font-weight:${n};font-display:swap;src:url(data:font/woff2;base64,${readFileSync(`${thm}thmanyahsans-${w}.woff2`).toString('base64')}) format("woff2")}`);
writeFileSync(`${out}/thmanyah.css`, faces.join('\n') + '\n');
for (const w of ['Regular', 'Medium', 'Bold']) rmSync(`${out}/thmanyahsans-${w}.woff2`, { force: true });   // loose copies from older builds
console.log(`vendor assets copied (${faces.length ? 'with' : 'WITHOUT'} the Thmanyah typeface)`);
