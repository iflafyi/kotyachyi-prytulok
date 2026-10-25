# builds dev/test/t/index.html from the source with local three.js and the mock Supabase client
import re, shutil, os
here = os.path.dirname(os.path.abspath(__file__)); src = os.path.join(here, '..', 'kotyachyi-prytulok.html')
s = open(src, encoding='utf-8').read()
s = s.replace('https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.min.js', 'http://127.0.0.1:8765/node_modules/three/build/three.module.min.js')
s = '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' + s
os.makedirs(os.path.join(here, 't'), exist_ok=True)
open(os.path.join(here, 't', 'index.html'), 'w', encoding='utf-8').write(s)
art = os.path.join(here, '..', 'art'); dst = os.path.join(here, 't', 'art')
if os.path.isdir(art): shutil.copytree(art, dst, dirs_exist_ok=True)
print('ok')
