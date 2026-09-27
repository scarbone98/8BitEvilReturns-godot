// Screenshots the web build. Usage: node tools/shot.mjs "<query>" out.png [waitMs] [clicks JSON]
// Needs a static server on :8791 serving build/web (python3 -m http.server).
import { chromium } from 'playwright';
const [, , query = '', out = 'shot.png', wait = '4000', clicks = '[]'] = process.argv;
const b = await chromium.launch({ executablePath: '/home/sami/.nix-profile/bin/chromium',
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const p = await b.newPage({ viewport: { width: 375, height: 667 }, deviceScaleFactor: 1 });
p.on('console', m => { if (/error|ERROR/.test(m.text())) console.log('console:', m.text()); });
p.on('pageerror', e => console.log('pageerror:', e.message));
await p.goto((process.env.BASE || 'http://127.0.0.1:8791') + '/index.html' + query);
await p.waitForTimeout(Number(wait));
for (const c of JSON.parse(clicks)) {
  if (c.key) await p.keyboard.press(c.key); else await p.mouse.click(c.x, c.y);
  await p.waitForTimeout(c.wait ?? 800);
}
await p.screenshot({ path: out });
await b.close();
