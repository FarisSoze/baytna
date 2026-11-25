// Copies runtime assets from node_modules into www/vendor so the app works offline inside the native shell.
import { cpSync, mkdirSync } from 'node:fs';
const out = 'www/vendor';
mkdirSync(out, { recursive: true });
const font = 'node_modules/@fontsource-variable/readex-pro/files/';
for (const f of ['readex-pro-arabic-wght-normal.woff2', 'readex-pro-latin-wght-normal.woff2']) cpSync(font + f, `${out}/${f}`);
cpSync('node_modules/@supabase/supabase-js/dist/umd/supabase.js', `${out}/supabase.js`);
console.log('vendor assets copied');
