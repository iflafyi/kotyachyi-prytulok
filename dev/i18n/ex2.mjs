import fs from 'fs'; import * as acorn from 'acorn'; import * as walk from 'acorn-walk';
const html = fs.readFileSync('../../index.html','utf8');
const si = html.lastIndexOf('<script>')+8, se = html.lastIndexOf('</script>');
const js = html.slice(si, se), markup = html.slice(0, si) + html.slice(se);
const ast = acorn.parse(js, {ecmaVersion:'latest', sourceType:'script'});
const CY = /[А-Яа-яЄєІіЇїҐґ’]/;
const raw = [];
const skipArr = new Set();
walk.full(ast, n => {
  if (n.type==='VariableDeclarator' && ['NAMES','VISITOR_NAMES','TRAITS'].includes(n.id.name)) skipArr.add(n.init);
  if (n.type==='Property' && n.value.type==='ArrayExpression' && n.key && ['dog','rat','fish','cat'].includes(n.key.name) && n.value.elements.every(e=>e && e.type==='Literal' && typeof e.value==='string' && !/\s/.test(e.value))) skipArr.add(n.value);
});
const skipped = new Set();
for (const a of skipArr) for (const e of a.elements||[]) if (e && e.type==='Literal') skipped.add(e.value);
walk.full(ast, n => {
  if (n.type==='Literal' && typeof n.value==='string' && !n.regex && CY.test(n.value)) raw.push(n.value);
  if (n.type==='TemplateElement' && n.value.cooked && CY.test(n.value.cooked)) raw.push(n.value.cooked);
});
raw.push(markup.replace(/<style[\s\S]*?<\/style>/,''));
const out = new Set();
const EDGE = /^[\s·:;,.!?—–\-()«»"'\/+×%…*\d]+|[\s·:;,.!?—–\-()«»"'\/+×%…*\d]+$/g;
for (const s of raw){
  const attrs = [...s.matchAll(/(?:aria-label|title|placeholder|alt)="([^"$]*)"/g)].map(m=>m[1]);
  const parts = s.replace(/<[^>]*>/g, '\u0000').split('\u0000').concat(attrs);
  for (let p of parts){ if (/^[^<]*>/.test(p)) p = p.replace(/^[^<]*>/, ''); if (/<[^>]*$/.test(p)) p = p.replace(/<[^>]*$/, ''); for (let q of p.split(/\n+/)){ if (/="[^"]*"?/.test(q) && !/[«»]/.test(q)) q = q.replace(/^.*"\s*/, ''); q = q.replace(EDGE,'').replace(/\s+/g,' '); if (q.length && CY.test(q) && !skipped.has(q)) out.add(q); } }
}
const arr = [...out].sort((a,b)=>b.length-a.length);
fs.writeFileSync('uk_static.json', JSON.stringify(arr, null, 1));
console.log(arr.length, arr.reduce((a,s)=>a+s.length,0));
