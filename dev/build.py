"""Usage (from anywhere): python3 dev/build.py BUILD_ID  -> writes index.html, version.json, sw.js, PWA files and art/ into the repo root.
Будує версію гри для простого хостингу без акаунтів: прогрес у браузері + код/файл збереження."""
import re, sys, json, datetime
import os as _os
_os.chdir(_os.path.dirname(_os.path.abspath(__file__)) + '/..')  # paths below are relative to the repo root
SRC, OUT = 'dev/kotyachyi-prytulok.html', '.'
BUILD = sys.argv[1] if len(sys.argv) > 1 else datetime.datetime.utcnow().strftime('%Y%m%d%H%M')
s = open(SRC).read()
def rep(old, new):
    global s
    assert old in s, 'MISSING: ' + old[:90]
    s = s.replace(old, new, 1)
title = re.search(r'<title>.*?</title>\n', s).group(0)
s = s.replace(title, '', 1).replace('<meta name="claude:viewport-fit-sides" content="cover">\n', '', 1)

rep('</style>', '''
.updbar{position:fixed;left:50%;transform:translateX(-50%);bottom:calc(86px + env(safe-area-inset-bottom,0px));z-index:47;background:var(--ink);color:var(--bg);
  border-radius:14px;padding:10px 12px;display:flex;gap:10px;align-items:center;box-shadow:0 6px 20px rgb(0 0 0 / .25);max-width:calc(100% - 32px)}
.updbar .btn{background:var(--rose);border-color:var(--rose);color:var(--rose-ink)}
</style>''')
rep('<script>\n/* ====', '''<script src="config.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.117.2/dist/umd/supabase.js"></script>
<script>
/* ====''')
rep('<div class="toasts" id="toasts" aria-live="polite"></div>', '''<div class="toasts" id="toasts" aria-live="polite"></div>
<div class="updbar" id="updBar" hidden><span>Вийшла нова версія гри</span><button class="btn" type="button" id="updBtn">Оновити</button></div>''')

# резервна копія: код + файл
rep("""    <p class="small muted" style="margin:0">Прогрес зберігається сам. Код нижче — запасний варіант, щоб перенести гру вручну.</p>""",
"""    <p class="small muted" style="margin:0">Прогрес зберігається в цьому браузері. Щоб перенести гру на інший пристрій чи не втратити її, якщо браузер очиститься, збережи код або файл. Час від часу роби нову копію.</p>
    <div class="btns"><button class="btn primary" data-act="savefile">Зберегти у файл</button><button class="btn" data-act="loadfile">Відкрити файл збереження</button></div>
    <input type="file" id="saveFileInput" accept=".txt,text/plain" hidden>""")
rep("""  spin(){ spinWheel(); },""", """  spin(){ spinWheel(); },
  savefile(){ const code = btoa(unescape(encodeURIComponent(serialize())));
    const d = new Date(), name = `kotyachyi-prytulok-${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}.txt`;
    const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([code], {type:'text/plain'})); a.download = name;
    document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
    toast('Файл збереження завантажено'); },
  loadfile(){ const inp = document.getElementById('saveFileInput'); inp.value = '';
    inp.onchange = async () => { const f = inp.files && inp.files[0]; if (!f) return;
      document.getElementById('importBox').value = (await f.text()).trim(); actions.import(); };
    inp.click(); },""")

rep("""window.claude?.hot?.snapshot?.(() => ({ state: W }));
window.claude?.hot?.ready ? window.claude.hot.ready(start) : start(window.claude?.hot?.data ?? {});""", '''/* ================= Простий хостинг: збереження в браузері + оновлення ================= */
const BUILD = '%BUILD%';
aiOff = true; sampleFn = null;   // живі розмови з Claude тут не підключені — котики відповідають готовими фразами
async function checkUpdate(){
  try { const r = await fetch('version.json?t=' + Date.now(), { cache:'no-store' }); if (!r.ok) return;
    const v = await r.json(); if (v.build && v.build !== BUILD) document.getElementById('updBar').hidden = false; } catch(e){}
}
document.getElementById('updBtn').addEventListener('click', () => { if (S) saveLocal(); location.reload(); });
setInterval(checkUpdate, 5*60000);
document.addEventListener('visibilitychange', () => { if (!document.hidden) checkUpdate(); });
window.addEventListener('pagehide', () => { if (S) saveLocal(); });
/* Переїзд зі старої адреси: стара сторінка передає збереження в #kpmove=… (стиснуте) або #kpmovej=… */
async function kpImport(){
  const h = location.hash || ''; let raw = null;
  try {
    if (h.startsWith('#kpmove=')){
      let b = h.slice(8).replace(/-/g,'+').replace(/_/g,'/'); while (b.length % 4) b += '=';
      const bytes = Uint8Array.from(atob(b), ch => ch.charCodeAt(0));
      raw = await new Response(new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'))).text();
    } else if (h.startsWith('#kpmovej=')) raw = decodeURIComponent(h.slice(9));
  } catch(e){ console.warn('kpImport', e); }
  if (h.startsWith('#kpmove')) try { history.replaceState(null, '', location.pathname + location.search); } catch(e){}
  if (!raw) return;
  try {
    const inc = migrate(JSON.parse(raw)); if (!inc || !inc.houses) return;
    const score = w => Object.values(w.houses||{}).reduce((a, x) => a + (+x.xp||0), 0);
    let cur = null; try { const r = localStorage.getItem(LOCAL_KEY); cur = r ? migrate(JSON.parse(r)) : null; } catch(e){}
    if (cur && cur.houses && (score(cur) > score(inc) || (score(cur) === score(inc) && (cur.savedAt||0) >= (inc.savedAt||0)))) return;
    localStorage.setItem(LOCAL_KEY, raw);
    setTimeout(() => toast('Прогрес перенесено на нову адресу гри 🐾'), 1500);
  } catch(e){ console.warn('kpImport', e); }
}
kpImport().finally(() => start({}));''')
s = s.replace('%BUILD%', BUILD)
head = f'''<!doctype html>
<html lang="uk">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="robots" content="noindex,nofollow">
<meta name="theme-color" content="#D94F74">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
<meta name="apple-mobile-web-app-title" content="Притулок">
<link rel="manifest" href="manifest.webmanifest">
<link rel="icon" type="image/png" href="icon-192.png">
<link rel="apple-touch-icon" href="apple-touch-icon.png">
<script>window.KP_STATIC = true;</script>
{title.strip()}
<style>:root{{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}}body{{margin:0;font:14px/1.4 system-ui,-apple-system,"Segoe UI",sans-serif}}img{{max-width:100%}}[hidden]{{display:none!important}}</style>
</head>
<body>
'''
open(f'{OUT}/index.html', 'w').write(head + s + '\n</body>\n</html>\n')
json.dump({'build': BUILD}, open(f'{OUT}/version.json', 'w'))
import shutil, os
for f in os.listdir('dev/pwa'):
    if f == 'sw.js': open(f'{OUT}/sw.js', 'w').write(open('dev/pwa/sw.js').read().replace('%BUILD%', BUILD))
    else: shutil.copy('dev/pwa/' + f, f'{OUT}/' + f)
os.makedirs(f'{OUT}/art', exist_ok=True)
for f in os.listdir('dev/art'): shutil.copy('dev/art/' + f, f'{OUT}/art/' + f)
print('built', BUILD)
