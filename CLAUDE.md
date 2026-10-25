# Котячий притулок — notes for Claude

Browser game (Ukrainian UI + Russian translation) that the owner (GitHub `iflafyi`, player «Дмитро-Пісюнчик») builds for his girlfriend and friends.
Live site: https://iflafyi.github.io/kotyachyi-prytulok/ (GitHub Pages from `main`, repo root). Talk to the owner in Ukrainian.

## Owner's preferences
- Deploy straight to the site (commit + push to `main`). Do **not** send test copies into the chat and do not republish the old claude.ai artifact.
- Bundle many requested features into one update when possible.
- When the chat gets long (usage grows fast, the conversation was auto-summarised, or a new big topic starts), tell him it is time to open a new chat.
- Short summaries at the end, no step-by-step recaps.

## Layout
- `dev/kotyachyi-prytulok.html` — **the only source file** (~7000 lines: HTML + CSS + one big script). Edit this.
- `dev/build.py BUILD_ID` — builds the site into the repo root: `index.html`, `version.json`, `sw.js` (from `dev/pwa/sw.js`, cache name uses BUILD_ID), PWA icons/manifest, `art/`. Never edit `index.html` by hand.
- `config.js` (root) — Supabase URL + publishable key; not touched by the build.
- `dev/art/` — the two hand-drawn cats by the owner's sister (`sislime`, `sissiam`, rarity «Авторський», index 12). Shown as `<image>` via `COATS[k].art`.
- `dev/test/` — mock backend for Playwright tests: `mktest.py` builds `dev/test/t/`, `kvserver.py t` serves it on :8767 with a `/kv/<key>` store, `cors.py .` serves three.js from `dev/test/node_modules` on :8765 (`npm i three@0.160.0`). Reset mock data: `curl -X PUT -d null http://127.0.0.1:8767/kv/<key>`.
- `dev/i18n/` — Russian: `RU_DICT` (fragment dictionary inside the source) is applied at runtime by `toRu`/`xl` through a MutationObserver. `add_ru.py pairs.json` adds entries; `ex2.mjs` + `rucheck.py` list untranslated fragments. Put `data-nol10n` on user-generated text (nicknames, messages).
- `dev/sql/` — snapshot of DB functions and tables (reference only; live DB is the truth).

## Deploy
```
python3 dev/build.py $(date -u +%Y%m%d%H%M)
git add -A && git commit -m "..." && git push origin main
```
Pages updates in ~1 min; check `https://iflafyi.github.io/kotyachyi-prytulok/version.json`. Old Netlify site (meek-cobbler-069673) is only a redirect page that migrates localStorage saves to the new address — do not deploy there.

## Backend: Supabase project `nsdjlohfagslhfaygstp`
- Client never touches tables directly (except legacy `saves` for email accounts). Everything goes through SECURITY DEFINER RPCs authenticated with `trade_check(p_id, p_secret)` (player id + secret stored in the save, `W.player`).
- Admin: table `admins` holds the owner's player id `c35c70a4-40d8-4667-800f-38265b9543a4`; `admin_check` guards admin RPCs; client `DEV_IDS` shows the «Розробник» badge and the dev panel (Settings → Панель розробника).
- Realtime: broadcast channels `kp-chat`, `kp-dm-<playerId>` (events m, gift, fr, lend, req, help, coexp, duel, r), `kp-club-<id>`, arena `kp-arena` + `kp-room-<CODE>` (presence + broadcast).
- `apply_migration` gets cancelled when the SQL contains the words delete/drop/revoke — use status/active flags instead of deleting rows.

## Game model (quick map)
- World `W` with `houses{cat,dog,rat,fish}`; `S` = current house. Shared fields live on `W` and are bound onto houses (`SHARED`, `bindShared`). `migrate()` fills new fields from `worldDefaults()`/`defaults()` — add new save fields there.
- Rarities 0..11 (`RAR_NAMES`, `RAR_MULT`, `SHARD_NEED`) + 12 «Авторський». Coats in `COATS` (`sp`, `rar`, optional `secret`, `art`). `coatsOf(sp)`, `rollPool`.
- Features are mostly appended blocks before `function devStart(){`: dev panel/PWA/announcements, social (friends, feed, help, lending), clubs/world event/joint expeditions, arena games/duels/chat reactions/stickers/contests. Existing functions are extended by re-assigning them (`{ const f0 = fn; fn = function(){ ... f0() ... }; }`).
- Startup hooks are called from `start()` (`devStart`, `socStart`, `clubStart`, `funStart`).
