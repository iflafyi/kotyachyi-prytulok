"""Lists Ukrainian UI fragments that the Russian translator does not cover yet.
Needs: cd dev/i18n && npm i && node ex2.mjs   (writes uk_static.json from the built index.html)
and the mock test page served (see dev/test/mktest.py). Output: dev/i18n/miss.txt"""
import asyncio, json, re, os
from playwright.async_api import async_playwright
os.chdir(os.path.dirname(os.path.abspath(__file__)))
UK = re.compile('[іїєґІЇЄҐ’]')
async def main():
    a = json.load(open('uk_static.json'))
    async with async_playwright() as p:
        b = await p.chromium.launch(); pg = await b.new_page()
        await pg.goto('http://127.0.0.1:8767/index.html'); await pg.wait_for_timeout(1500)
        cand = [x for x in a if UK.search(x)]
        bad = await pg.evaluate("(c)=>c.filter(s=>/[іїєґІЇЄҐ’]/.test(toRu(s)))", cand)
        await b.close()
    bad = [x for x in bad if not x.startswith(('Правила відповіді','Відповідай від імені','З тобою говорить','Ти граєш','Ми граємо','Інші котики')) and 'p{L}' not in x]
    open('miss.txt', 'w').write('\n'.join(bad)); print(len(bad), 'missing')
asyncio.run(main())
