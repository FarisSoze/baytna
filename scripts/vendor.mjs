// Copies runtime assets from node_modules into www/vendor so the app works offline inside the native shell.
import { cpSync, mkdirSync, existsSync } from 'node:fs';
const out = 'www/vendor';
mkdirSync(out, { recursive: true });
const font = 'node_modules/@fontsource-variable/readex-pro/files/';
for (const f of ['readex-pro-arabic-wght-normal.woff2', 'readex-pro-latin-wght-normal.woff2']) cpSync(font + f, `${out}/${f}`);
cpSync('node_modules/@supabase/supabase-js/dist/umd/supabase.js', `${out}/supabase.js`);
// The Thmanyah typeface is licensed: its files stay out of the repository. Locally they sit in designs/fonts,
// in CI they are unpacked into the same folder from the encrypted bundle. Without them the app falls back to Readex Pro.
const thm = 'designs/fonts/';
let n = 0;
for (const w of ['Regular', 'Medium', 'Bold']) if (existsSync(`${thm}thmanyahsans-${w}.woff2`)) { cpSync(`${thm}thmanyahsans-${w}.woff2`, `${out}/thmanyahsans-${w}.woff2`); n++; }
console.log(`vendor assets copied (${n ? 'with' : 'WITHOUT'} the Thmanyah typeface)`);
