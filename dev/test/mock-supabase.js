(function(){
const kv = { get: async k => (await fetch('/kv/'+k)).json(), put: (k,v) => fetch('/kv/'+k, {method:'PUT', body: JSON.stringify(v)}) };
window.supabase = { createClient(){
  let session = JSON.parse(localStorage.getItem('mock_sess') || 'null'); const subs = [];
  const fire = (ev, s) => subs.forEach(f => f(ev, s));
  return {
    auth: {
      async getSession(){ return {data:{session}}; },
      onAuthStateChange(cb){ subs.push(cb); return {data:{subscription:{unsubscribe(){}}}}; },
      async signUp({email,password}){ const u = (await kv.get('users')) || {}; if (u[email]) return {data:{user:{identities:[]},session:null},error:null};
        u[email] = {id:'user-'+Object.keys(u).length, password}; await kv.put('users', u);
        session = {user:{id:u[email].id, email}}; localStorage.setItem('mock_sess', JSON.stringify(session)); fire('SIGNED_IN', session); return {data:{session, user:session.user}, error:null}; },
      async signInWithPassword({email,password}){ const u = ((await kv.get('users'))||{})[email]; if (!u || u.password!==password) return {data:{}, error:{message:'Invalid login credentials'}};
        session = {user:{id:u.id, email}}; localStorage.setItem('mock_sess', JSON.stringify(session)); fire('SIGNED_IN', session); return {data:{session, user:session.user}, error:null}; },
      async signOut(){ session = null; localStorage.removeItem('mock_sess'); fire('SIGNED_OUT', null); return {error:null}; },
      async resetPasswordForEmail(){ return {error:null}; }, async updateUser(){ return {data:{}, error:null}; }
    },
    from(t){ return {
      select(){ return { eq(c, v){ return { async maybeSingle(){ const d = (await kv.get('saves'))||{}; return {data: d[v] || null, error:null}; } }; } }; },
      async upsert(row){ if (!session || session.user.id !== row.user_id) return {error:{message:'rls'}}; const d = (await kv.get('saves'))||{}; d[row.user_id] = row; await kv.put('saves', d); return {error:null}; }
    }; },
    channel(name, opts){
      const key = (opts && opts.config && opts.config.presence && opts.config.presence.key) || Math.random().toString(36).slice(2);
      const bc = new BroadcastChannel('mock-' + name); const handlers = []; const peers = new Map(); let mine = null, hb = null;
      const fireSync = () => handlers.filter(h => h.type==='presence').forEach(h => h.cb());
      const st = () => { const o = {}; const t = Date.now(); for (const [k, v] of peers) if (t - v.at < 2500) o[k] = [v.meta]; if (mine) o[key] = [mine]; return o; };
      bc.onmessage = e => { const m = e.data; if (m.k==='p'){ if (m.meta) peers.set(m.key, {meta:m.meta, at:Date.now()}); else peers.delete(m.key); fireSync(); if (m.ask && mine) bc.postMessage({k:'p', key, meta:mine}); }
        else if (m.k==='b') handlers.filter(h => h.type==='broadcast' && h.event===m.event).forEach(h => h.cb({payload:m.payload})); };
      const ch = {
        on(type, f, cb){ handlers.push({type, event:f.event, cb}); return ch; },
        subscribe(cb){ setTimeout(() => { bc.postMessage({k:'p', key, meta:null, ask:true}); cb && cb('SUBSCRIBED'); }, 30);
          hb = setInterval(() => { if (mine) bc.postMessage({k:'p', key, meta:mine}); let ch2 = false; for (const [k,v] of peers) if (Date.now()-v.at > 2500){ peers.delete(k); ch2 = true; } if (ch2) fireSync(); }, 700); return ch; },
        async track(meta){ mine = meta; bc.postMessage({k:'p', key, meta}); fireSync(); return 'ok'; },
        async untrack(){ mine = null; bc.postMessage({k:'p', key, meta:null}); fireSync(); return 'ok'; },
        presenceState: st,
        async send(m){ bc.postMessage({k:'b', event:m.event, payload:m.payload}); return 'ok'; },
        unsubscribe(){ clearInterval(hb); if (mine) bc.postMessage({k:'p', key, meta:null}); bc.close(); }
      };
      return ch;
    },
    removeChannel(){},
    rpc: async (fn, a) => {
      const T = (await kv.get('trades')) || [];
      const save = () => kv.put('trades', T);
      if (fn==='trade_create'){ const id = 't'+Date.now()+Math.random().toString(16).slice(2,6); T.push({id, seller:a.p_id, seller_nick:'Я-'+a.p_id.slice(0,4), offer:a.p_offer, want:a.p_want, status:'open'}); await save(); return {data:id, error:null}; }
      if (fn==='trade_list') return {data: T.filter(t => t.status==='open' || (t.seller===a.p_id && t.status==='taken')).map(t => Object.assign({}, t, {mine: t.seller===a.p_id})), error:null};
      if (fn==='trade_take'){ const t = T.find(x => x.id===a.p_trade && x.status==='open' && x.seller!==a.p_id); if (!t) return {data:null, error:{message:'trade gone'}}; t.status='taken'; t.paid=a.p_paid; t.buyer_nick='Покупець'; await save(); return {data:t.offer, error:null}; }
      if (fn==='trade_cancel'){ const t = T.find(x => x.id===a.p_trade && x.status==='open' && x.seller===a.p_id); if (!t) return {data:null, error:{message:'trade gone'}}; t.status='cancelled'; await save(); return {data:t.offer, error:null}; }
      if (fn==='trade_close'){ const t = T.find(x => x.id===a.p_trade && x.status==='taken' && x.seller===a.p_id); if (!t) return {data:null, error:{message:'trade gone'}}; t.status='closed'; await save(); return {data:t.paid, error:null}; }
      if (fn && fn.startsWith('gift_')){
        const G = (await kv.get('gifts')) || [];
        if (fn==='gift_send'){ G.push({id:G.length+1, at:new Date().toISOString(), from:a.p_id, nick:'N-'+a.p_id.slice(0,4), to:a.p_to, kind:a.p_kind, payload:a.p_payload, msg:a.p_msg||'', status:'sent'}); await kv.put('gifts', G); return {data:G.length, error:null}; }
        if (fn==='gift_list') return {data:G.filter(g => g.to===a.p_id && g.status==='sent').reverse(), error:null};
        if (fn==='gift_take'){ const g = G.find(x => x.id===a.p_gift && x.to===a.p_id && x.status==='sent'); if (!g) return {data:null, error:{message:'gift gone'}}; g.status='taken'; await kv.put('gifts', G); return {data:{kind:g.kind, payload:g.payload, nick:g.nick}, error:null}; }
      }
      if (fn && fn.startsWith('chat_')){
        const C = (await kv.get('chat')) || {m:[], i:[]};
        const out = m => ({id:m.id, at:m.at, from:m.from, nick:m.nick, body:m.body, img:m.img});
        if (fn==='chat_send'){ if (!a.p_body && !a.p_img) return {data:null, error:{message:'empty'}}; let img = null; if (a.p_img){ img = C.i.length+1; C.i.push({id:img, data:a.p_img}); }
          const m = {id:C.m.length+1, at:new Date().toISOString(), from:a.p_id, nick:'N-'+a.p_id.slice(0,4), to:a.p_to, body:a.p_body||'', img}; C.m.push(m); await kv.put('chat', C); return {data:{id:m.id}, error:null}; }
        if (fn==='chat_global') return {data:C.m.filter(m => !m.to && m.id > (a.p_after||0)).slice(-80).map(out), error:null};
        if (fn==='chat_dm') return {data:C.m.filter(m => m.to && ((m.from===a.p_id && m.to===a.p_with) || (m.from===a.p_with && m.to===a.p_id)) && m.id > (a.p_after||0)).map(out), error:null};
        if (fn==='chat_threads'){ const th = {}; for (const m of C.m) if (m.to && (m.from===a.p_id || m.to===a.p_id)){ const o = m.from===a.p_id ? m.to : m.from; th[o] = {with:o, nick:'N-'+o.slice(0,4), last_id:m.id, body:m.body, img:!!m.img, mine:m.from===a.p_id, online:true}; } return {data:Object.values(th).reverse(), error:null}; }
        if (fn==='chat_img'){ const i = C.i.find(x => x.id===a.p_img); return {data:i ? i.data : null, error:null}; }
      }
      if (fn && (fn.startsWith('club_') || fn.startsWith('world_') || fn==='admin_world' || fn==='contrib_push' || fn.startsWith('coexp_'))){
        const C = (await kv.get('club')) || {clubs:[], mem:{}, msgs:[], claims:{}, world:null, wc:{}, co:[]}; const sv = () => kv.put('club', C); const me = a && a.p_id; const nk = id => 'N-' + id.slice(0,4); const err = m => ({data:null, error:{message:m}});
        const lvl = x => { let l = 0; for (let i = 1; i <= 10; i++) if (x >= 2500*i*(i+1)) l = i; return l; };
        const fok = async (x, y) => { const X = (await kv.get('soc')) || {fr:[]}; return X.fr.some(f => f.st==='ok' && ((f.a===x && f.b===y) || (f.a===y && f.b===x))); };
        const view = c => ({id:c.id, name:c.name, emblem:c.emblem, owner:c.owner, week:'w', goal:c.goal, target:c.target, progress:c.progress, score:c.score, bank:c.bank, bxp:c.bxp, lvl:lvl(c.bxp), pets:c.pets,
          claimed: !!C.claims[c.id+':'+me], members: Object.entries(C.mem).filter(([, m]) => m.club===c.id).map(([id, m]) => ({id, nick:nk(id), role:m.role, contrib:m.contrib, total:0, online:true, seen_ago:0, level:2}))});
        if (fn==='club_list') return {data: C.clubs.filter(c => c.active).map(c => ({id:c.id, name:c.name, emblem:c.emblem, members:Object.values(C.mem).filter(m => m.club===c.id).length, score:c.score, lvl:lvl(c.bxp)})), error:null};
        if (fn==='club_create'){ if (C.mem[me] && C.mem[me].club) return err('already in club'); if (C.clubs.some(c => c.active && c.name.toLowerCase()===a.p_name.toLowerCase())) return err('name taken');
          const c = {id:C.clubs.length+1, name:a.p_name, emblem:a.p_emblem, owner:me, goal:'pet', target:900, progress:0, score:0, bank:0, bxp:0, pets:[], active:true}; C.clubs.push(c); C.mem[me] = {club:c.id, role:'owner', contrib:0}; await sv(); return {data:c.id, error:null}; }
        if (fn==='club_join'){ if (C.mem[me] && C.mem[me].club) return err('already in club'); C.mem[me] = {club:a.p_club, role:'member', contrib:0}; await sv(); return {data:null, error:null}; }
        if (fn==='club_leave'){ if (C.mem[me]) C.mem[me].club = 0; await sv(); return {data:null, error:null}; }
        if (fn==='club_kick'){ if (C.mem[a.p_who]) C.mem[a.p_who].club = 0; await sv(); return {data:null, error:null}; }
        const myc = C.mem[me] && C.mem[me].club ? C.clubs.find(c => c.id===C.mem[me].club) : null;
        if (fn==='club_get') return {data: myc ? view(myc) : null, error:null};
        if (fn==='club_claim'){ if (!myc) return err('no club'); if (myc.progress < myc.target) return err('not yet'); if (C.claims[myc.id+':'+me]) return err('gone'); C.claims[myc.id+':'+me] = 1; await sv(); return {data:{lvl:lvl(myc.bxp)}, error:null}; }
        if (fn==='club_donate'){ if (!myc) return err('no club'); let x = a.p_coins||0; if (a.p_pet){ x += 500*(1+(a.p_pet.rar||0)); myc.pets.push(Object.assign({}, a.p_pet, {by:nk(me)})); } myc.bank += a.p_coins||0; myc.bxp += x; await sv(); return {data:{lvl:lvl(myc.bxp), bxp:myc.bxp}, error:null}; }
        if (fn==='club_say'){ if (!myc) return err('no club'); C.msgs.push({id:C.msgs.length+1, at:new Date().toISOString(), club:myc.id, from:me, nick:nk(me), body:a.p_body}); await sv(); return {data:C.msgs.length, error:null}; }
        if (fn==='club_msgs_get') return {data: myc ? C.msgs.filter(m => m.club===myc.id && m.id > (a.p_after||0)) : [], error:null};
        if (fn==='contrib_push'){ for (const [k, v] of Object.entries(a.p_c||{})){ if (myc && k===myc.goal){ myc.progress += v; myc.score += v; C.mem[me].contrib += v; } if (C.world && k===C.world.kind){ C.world.progress += v; C.wc[me] = (C.wc[me]||0) + v; } } await sv(); return {data:{ok:true}, error:null}; }
        if (fn==='admin_world'){ C.world = {id:(C.world ? C.world.id : 0) + 1, kind:a.p_kind, title:a.p_title, target:a.p_target, progress:0, reward:a.p_reward, ends:Date.now()+a.p_hours*3600e3}; C.wc = {}; C.wcl = {}; await sv(); return {data:C.world.id, error:null}; }
        if (fn==='world_get') return {data: C.world ? Object.assign({}, C.world, {mine:C.wc[me]||0, claimed:!!(C.wcl||{})[me]}) : null, error:null};
        if (fn==='world_claim'){ if (!C.world || C.world.progress < C.world.target || !C.wc[me] || (C.wcl||{})[me]) return err('gone'); C.wcl = C.wcl || {}; C.wcl[me] = 1; await sv(); return {data:C.world.reward, error:null}; }
        if (fn==='coexp_create'){ if (!(await fok(me, a.p_to))) return err('not friends'); C.co.push({id:C.co.length+1, kind:a.p_kind, ms:a.p_ms, created:Date.now(), host:me, host_nick:nk(me), guest:a.p_to, guest_nick:nk(a.p_to), status:'open', ends:null}); await sv(); return {data:C.co.length, error:null}; }
        if (fn==='coexp_list') return {data: C.co.filter(x => (x.host===me || x.guest===me) && x.status!=='cancel').map(x => Object.assign({}, x, {mine:x.host===me})), error:null};
        if (fn==='coexp_join'){ const x = C.co.find(y => y.id===a.p_x && y.guest===me && y.status==='open'); if (!x) return err('gone'); x.status='go'; x.ends = Math.max(Date.now()+60000, x.created + x.ms*0.7); await sv(); return {data:{kind:x.kind, ends:x.ends, host_nick:x.host_nick}, error:null}; }
        return {data:null, error:null};
      }
      if (fn && (fn.startsWith('duel_') || fn.startsWith('contest_') || fn==='chat_react' || fn==='chat_reacts_get')){
        const Z = (await kv.get('fun')) || {du:[], ce:[], cv:[], cc:{}, re:{}}; const sv = () => kv.put('fun', Z); const me = a && a.p_id; const nk = id => 'N-' + id.slice(0,4); const err = m => ({data:null, error:{message:m}});
        if (fn==='duel_create'){ Z.du.push({id:Z.du.length+1, a:me, a_nick:nk(me), b:a.p_to, b_nick:nk(a.p_to), game:a.p_game, stake:a.p_stake, code:a.p_code, status:'open', winner:null, ca:false, cb:false}); await sv(); return {data:Z.du.length, error:null}; }
        if (fn==='duel_list') return {data: Z.du.filter(d => (d.a===me || d.b===me) && (['open','accepted'].includes(d.status) || (['done','void'].includes(d.status) && !(d.a===me ? d.ca : d.cb)))).map(d => Object.assign({}, d, {mine:d.a===me, claimed: d.a===me ? d.ca : d.cb})), error:null};
        if (fn==='duel_accept'){ const d = Z.du.find(x => x.id===a.p_duel && x.b===me && x.status==='open'); if (!d) return err('gone'); d.status='accepted'; d.acc=1; await sv(); return {data:{code:d.code, game:d.game, stake:d.stake, a_nick:d.a_nick}, error:null}; }
        if (fn==='duel_cancel'){ const d = Z.du.find(x => x.id===a.p_duel && (x.a===me || x.b===me) && x.status==='open'); if (!d) return err('gone'); d.status='cancel'; d.cb=true; await sv(); return {data:'cancel', error:null}; }
        if (fn==='duel_result'){ const d = Z.du.find(x => x.id===a.p_duel && x.a===me && x.status==='accepted'); if (d){ d.status='done'; d.winner=a.p_winner; await sv(); } return {data:null, error:null}; }
        if (fn==='duel_claim'){ const d = Z.du.find(x => x.id===a.p_duel); if (!d) return err('gone'); const isA = d.a===me; if (isA ? d.ca : d.cb) return {data:{kind:'none'}, error:null};
          if (d.status==='done'){ if (isA) d.ca = true; else d.cb = true; await sv(); return {data:{kind: d.winner===me ? 'win' : 'lose', amount: d.winner===me ? d.stake*2 : 0}, error:null}; }
          if (d.status==='void' || d.status==='cancel'){ if (isA) d.ca = true; else d.cb = true; await sv(); return {data:{kind:'refund', amount:d.stake}, error:null}; }
          return {data:{kind:'wait'}, error:null}; }
        const W_ = 'w2', PW = 'w1';
        const votes = id => Z.cv.filter(v => v.e===id && v.on).length;
        if (fn==='contest_enter'){ let e = Z.ce.find(x => x.week===W_ && x.kind===a.p_kind && x.from===me); if (!e){ e = {id:Z.ce.length+1, week:W_, kind:a.p_kind, from:me, nick:nk(me)}; Z.ce.push(e); } e.data = a.p_data; e.img = a.p_img; Z.cv.forEach(v => { if (v.e===e.id) v.on = false; }); await sv(); return {data:e.id, error:null}; }
        if (fn==='contest_list'){ const ent = w => Z.ce.filter(e => e.week===w && e.kind===a.p_kind).map(e => ({id:e.id, from:e.from, nick:e.nick, data:e.data, votes:votes(e.id), mine:e.from===me})).sort((x, y) => y.votes - x.votes || x.id - y.id);
          return {data:{week:W_, entries:ent(W_), myvotes:Z.cv.filter(v => v.voter===me && v.on && Z.ce.find(e => e.id===v.e && e.kind===a.p_kind && e.week===W_)).map(v => v.e), last:ent(PW).slice(0,3), claimed:!!Z.cc[PW+a.p_kind+me]}, error:null}; }
        if (fn==='contest_img'){ const e = Z.ce.find(x => x.id===a.p_entry); return {data:e ? e.img : null, error:null}; }
        if (fn==='contest_vote'){ const e = Z.ce.find(x => x.id===a.p_entry && x.week===W_); if (!e) return err('gone'); if (e.from===me) return err('own entry'); let v = Z.cv.find(x => x.voter===me && x.e===e.id);
          if (v && v.on){ v.on = false; await sv(); return {data:false, error:null}; } if (Z.cv.filter(x => x.voter===me && x.on && Z.ce.find(y => y.id===x.e && y.kind===e.kind && y.week===W_)).length >= 3) return err('too many');
          if (!v){ v = {voter:me, e:e.id}; Z.cv.push(v); } v.on = true; await sv(); return {data:true, error:null}; }
        if (fn==='contest_claim'){ const last = Z.ce.filter(e => e.week===PW && e.kind===a.p_kind).map(e => ({e, n:votes(e.id)})).sort((x, y) => y.n - x.n || x.e.id - y.e.id).slice(0, 3); const i = last.findIndex(x => x.e.from===me && x.n > 0);
          if (i < 0 || Z.cc[PW+a.p_kind+me]) return err('gone'); Z.cc[PW+a.p_kind+me] = 1; await sv(); return {data:i+1, error:null}; }
        if (fn==='chat_react'){ Z.re[a.p_msg] = Z.re[a.p_msg] || {}; if (a.p_emoji) Z.re[a.p_msg][me] = a.p_emoji; else delete Z.re[a.p_msg][me]; await sv(); return {data:null, error:null}; }
        if (fn==='chat_reacts_get'){ const out = []; for (const id of a.p_ids){ const r = Z.re[id]; if (!r) continue; const g = {}; for (const [p, e] of Object.entries(r)){ g[e] = g[e] || {msg:id, emoji:e, n:0, mine:false}; g[e].n++; if (p===me) g[e].mine = true; } out.push(...Object.values(g)); } return {data:out, error:null}; }
      }
      if (fn==='player_house') return {data:{nickname:'N-'+a.p_id.slice(0,4), online:true, seen_ago:0, level:2, coins:100, collection:2, house:{name:'Притулок', cats:[{name:'Мурчик', coat:'ginger', lvl:2, room:'main', happy:40, hunger:30},{name:'Рижик', coat:'calico', lvl:1, room:'main', happy:50, hunger:40}]}}, error:null};
      { const X = (await kv.get('soc')) || {fr:[], feed:[], vh:[], rq:[], ln:[]}; const sv = () => kv.put('soc', X); const nk = id => 'N-' + id.slice(0,4); const me = a.p_id; const err = m => ({data:null, error:{message:m}});
        const fok = (x, y) => X.fr.some(f => f.st==='ok' && ((f.a===x && f.b===y) || (f.a===y && f.b===x)));
        if (fn==='friend_request'){ if (fok(me, a.p_to)) return {data:'ok', error:null}; const rev = X.fr.find(f => f.a===a.p_to && f.b===me && f.st==='pending'); if (rev){ rev.st='ok'; await sv(); return {data:'ok', error:null}; }
          X.fr = X.fr.filter(f => !(f.a===me && f.b===a.p_to)); X.fr.push({a:me, b:a.p_to, st:'pending'}); await sv(); return {data:'pending', error:null}; }
        if (fn==='friend_answer'){ X.fr.forEach(f => { if (f.a===a.p_from && f.b===me && f.st==='pending') f.st = a.p_ok ? 'ok' : 'no'; }); await sv(); return {data:null, error:null}; }
        if (fn==='friend_remove'){ X.fr.forEach(f => { if ((f.a===me && f.b===a.p_other) || (f.b===me && f.a===a.p_other)) f.st='removed'; }); await sv(); return {data:null, error:null}; }
        if (fn==='friend_list') return {data: X.fr.filter(f => (f.a===me || f.b===me) && (f.st==='ok' || f.st==='pending')).map(f => { const o = f.a===me ? f.b : f.a; return {id:o, nick:nk(o), level:3, coins:100, cats:2, online:true, seen_ago:0, status: f.st==='ok' ? 'ok' : f.a===me ? 'out' : 'in'}; }), error:null};
        if (fn==='feed_post'){ X.feed.push({id:X.feed.length+1, at:Date.now(), from:me, nick:nk(me), kind:a.p_kind, data:a.p_data}); await sv(); return {data:null, error:null}; }
        if (fn==='feed_list') return {data: X.feed.filter(e => e.from===me || fok(me, e.from)).map(e => Object.assign({}, e, {mine:e.from===me})).reverse(), error:null};
        if (fn==='visit_help'){ if (X.vh.some(v => v.from===me && v.to===a.p_to && v.kind===a.p_kind)) return err('already helped'); X.vh.push({id:X.vh.length+1, from:me, nick:nk(me), to:a.p_to, kind:a.p_kind, sp:a.p_sp, claimed:false}); await sv(); return {data:6 - X.vh.filter(v => v.from===me).length, error:null}; }
        if (fn==='help_inbox'){ const r = X.vh.filter(v => v.to===me && !v.claimed); r.forEach(v => v.claimed = true); await sv(); return {data:r, error:null}; }
        if (fn==='help_today') return {data:{left: 6 - X.vh.filter(v => v.from===me).length, done: X.vh.filter(v => v.from===me).map(v => v.to+':'+v.kind)}, error:null};
        if (fn==='req_create'){ if (X.rq.some(r => r.from===me && r.status==='open')) return err('already open'); X.rq.push({id:X.rq.length+1, at:Date.now(), from:me, nick:nk(me), kind:a.p_kind, amount:a.p_amount, sp:a.p_sp, rar:a.p_rar, note:a.p_note, status:'open', claimed:false}); await sv(); return {data:X.rq.length, error:null}; }
        if (fn==='req_list') return {data: X.rq.filter(r => (r.from===me && (r.status==='open' || (r.status==='done' && !r.claimed))) || (r.status==='open' && fok(me, r.from))).map(r => Object.assign({}, r, {mine:r.from===me})).reverse(), error:null};
        if (fn==='req_fill'){ const r = X.rq.find(x => x.id===a.p_req && x.status==='open' && x.from!==me && fok(me, x.from)); if (!r) return err('gone'); r.status='done'; r.helper=nk(me); r.payload=a.p_payload; await sv(); return {data:{kind:r.kind, amount:r.amount, nick:r.nick, to:r.from}, error:null}; }
        if (fn==='req_take'){ const r = X.rq.find(x => x.id===a.p_req && x.from===me && x.status==='done' && !x.claimed); if (!r) return err('gone'); r.claimed = true; await sv(); return {data:{kind:r.kind, amount:r.amount, payload:r.payload, nick:r.helper}, error:null}; }
        if (fn==='req_cancel'){ X.rq.forEach(r => { if (r.id===a.p_req && r.from===me && r.status==='open') r.status='cancel'; }); await sv(); return {data:null, error:null}; }
        if (fn==='lend_send'){ if (!fok(me, a.p_to)) return err('not friends'); X.ln.push({id:X.ln.length+1, owner:me, owner_nick:nk(me), to:a.p_to, to_nick:nk(a.p_to), pet:a.p_pet, until:Date.now()+a.p_hours*3600e3, status:'sent'}); await sv(); return {data:X.ln.length, error:null}; }
        if (fn==='lend_list') return {data: X.ln.filter(l => (l.owner===me || l.to===me) && l.until > Date.now() && (l.status==='sent' || l.status==='active')).map(l => Object.assign({}, l, {mine:l.owner===me})), error:null};
        if (fn==='lend_take'){ const l = X.ln.find(x => x.id===a.p_lend && x.to===me && x.status==='sent'); if (!l) return err('gone'); l.status='active'; await sv(); return {data:{pet:l.pet, until:l.until, owner:l.owner, owner_nick:l.owner_nick}, error:null}; }
        if (fn==='lend_cancel'){ const l = X.ln.find(x => x.id===a.p_lend && ((x.owner===me && x.status==='sent') || (x.to===me && (x.status==='sent' || x.status==='active')))); if (!l) return err('gone'); l.status = l.owner===me && l.status==='sent' ? 'cancel' : 'back'; if (l.to===me) l.until = Date.now(); await sv(); return {data:l.status, error:null}; }
        if (fn==='lend_status') return {data: X.ln.filter(l => a.p_ids.includes(l.id) && (l.owner===me || l.to===me)).map(l => ({id:l.id, status:l.status, until:l.until})), error:null};
      }
      { const D = (await kv.get('dev')) || {ann:[], ev:[], bk:{}, rs:{}}; const sv = () => kv.put('dev', D);
        const ADM = 'c35c70a4-40d8-4667-800f-38265b9543a4', nadm = {data:null, error:{message:'not admin'}};
        if (fn==='admin_check') return a.p_id===ADM ? {data:'Dev', error:null} : nadm;
        if (fn.startsWith('admin_') && a.p_id!==ADM) return nadm;
        if (fn==='announce_list') return {data:D.ann.filter(x => x.active).reverse(), error:null};
        if (fn==='events_active') return {data:D.ev.filter(x => x.active && x.ends > Date.now()), error:null};
        if (fn==='admin_announce'){ const id = D.ann.length+1; D.ann.push({id, kind:a.p_kind, title:a.p_title, body:a.p_body, active:true}); await sv(); return {data:id, error:null}; }
        if (fn==='admin_announce_off'){ D.ann.forEach(x => { if (x.id===a.p_ann) x.active = false; }); await sv(); return {data:null, error:null}; }
        if (fn==='admin_event'){ const id = D.ev.length+1; D.ev.push({id, kind:a.p_kind, starts:Date.now(), ends:Date.now()+a.p_hours*3600e3, active:true}); await sv(); return {data:id, error:null}; }
        if (fn==='admin_event_off'){ D.ev.forEach(x => { if (x.id===a.p_event) x.active = false; }); await sv(); return {data:null, error:null}; }
        if (fn==='backup_save'){ D.bk[a.p_id] = {state:a.p_state, at:Date.now(), prev_state:(D.bk[a.p_id]||{}).state || null, prev_at:Date.now()-13*3600e3}; await sv(); return {data:null, error:null}; }
        if (fn==='admin_backup_get') return {data:D.bk[a.p_player] || null, error:null};
        if (fn==='admin_restore'){ D.rs[a.p_player] = a.p_state; await sv(); return {data:null, error:null}; }
        if (fn==='restore_check'){ const st = D.rs[a.p_id] || null; delete D.rs[a.p_id]; await sv(); return {data:st, error:null}; }
        if (fn==='admin_stats') return {data:{players:6, online:2, today:5, week:6, new_week:3, coins:704000, pets:120, msgs_today:40, gifts_today:7, top:[{coat:'ginger', n:9},{coat:'calico', n:7}]}, error:null};
        if (fn==='admin_gift'){ const G = (await kv.get('gifts')) || []; const to = a.p_to ? [a.p_to] : ['bbbb-0000-4000-8000-000000000000'];
          for (const t of to) G.push({id:G.length+1, at:new Date().toISOString(), from:a.p_id, nick:'Dev', to:t, kind:a.p_kind, payload:a.p_payload, msg:a.p_msg||'', status:'sent'}); await kv.put('gifts', G); return {data:to.length, error:null}; }
        if (fn==='leaderboard') return {data:[{id:ADM, nickname:'Дмитро', coins:5000, cats:3, collection:3, level:2, online:true, seen_ago:0},{id:'bbbb-0000-4000-8000-000000000000', nickname:'bbbb', coins:100, cats:1, collection:1, level:1, online:true, seen_ago:0}], error:null};
      }
      return {data:[], error:null};
    }
  };
} };
})();
