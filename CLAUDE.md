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
- Startup hooks are called from `start()` (`devStart`, `socStart`, `clubStart`, `funStart`, `uiStart`).
- UI block («Інтерфейс», just before `devStart`): every `.pickpet` gets `${pickData(c)}`; `pickEnhance()` (MutationObserver on `#panel`/`#modalRoot`) adds search/sort/rarity filter to any `.pickgrid2` with ≥6 pets; `pickLocked(list, prefix)` renders unavailable pets with a reason (`pickWhy`); long-press/right-click → `quickCard`; `askConfirm(html, okLabel)` → Promise<bool> for irreversible actions; adventure tiles `ADV_TILES` + `advDots()`; last sections saved in localStorage `kp-ui-v1`; seasonal theme `data-season` (halloween/winter/spring, `W.settings.season` auto/off).
- Gifts: `canGift` allows author cats (`secret:'author'`); other secrets, borrowed, sick, away can't be gifted. Trade/lend/merge still use `canTrade`/`canMerge` (no secrets).
- Icons: `ICON_MAP` (text → emoji, exact or prefix match, run through `xl()` for RU/other species) is applied by `iconPass()` (MutationObserver) to `ICON_SEL` elements as `<span class="eic">`; add new labels there. Rescue cases use `SIT_IC`/`TOOL_IC` via `sitIc(sit)`, achievements `ACH_IC` on the medal.
- Deep pet progression block («Глибока прокачка», before `devStart`): `perkExtra(c,k)` adds talents (`c.tal`, `TALENTS`), amulet (`c.amu`, `AMULETS`, inventory `S.amulets`) and outfit set (`SETS`, scaled by item levels `S.wardLvl`) into `perkVal`, so every perk key (gold, food, mood, health, charm, pet, xp, luck, rescue, fish, aura) plus new `power`/`find`/`amu` work everywhere. Forge (`forgeup`/`forgepick`, perk tier 3 = «Легендарний» needs awakening), awakening `c.awake` (lvl cap `catMaxLvl(c)` = 20, aura ring in 3D, +1 perk slot), rarity ascend (changes `c.coat` to a next-rarity coat), profession specs `c.prof.spec` 1 = master ×1.5 / 2 = `PROF_ALT` bonus in `profSum`, collection bonuses `collBonus()` in `globalMult` + `S.collClaim`.
- Talents: 4 branches (`TAL_BR` inc/care/adv/luck), ult talents at req 10 and 18; `c.talBuy` = bought points (max `TALBUY_MAX`, `talBuyCost`). Shelter `UPGRADES` have `m0` = old max (levels above it cost ×2.5·1.3^n, effects above old max are softer); new global upgrades souvenir/gym/maps/clinic/school/garden/amulab read via `upLv(k)`.
- Bulk open/spin («масове відкриття», after `openChest`): `BULK_N` = [5,10,20,30], `openChestBulk(n)` runs `openChest()` with global `chestBulk` collector set (no per-chest modal; amulet wrapper and author chest also record into it), `spinWheelBulk(n)` spins without animation (free/bonus spins first, stops when shelter full or coins run out), cats get auto names; `bulkSummary`/`bulkModal`/`bulkBtns` render the result.
- `dev/IDEAS.md` — numbered list of ideas for the next big update; the owner will pick numbers.

## Multi-account (several players on one device)
- Registry in localStorage `kp-profiles-v1` `{active, list:[{id,name,at}]}`; `PROF_ID` fixed per page load. Profile `main` keeps the legacy keys (`kotoprytulok_save`, auth `kotoprytulok-auth`); others use `__<id>` suffixes (`profSaveKey`/`profAuthKey`). Switching = save, set active, reload (`profSwitch`). UI: Settings → «Акаунти на цьому пристрої» (`renderProfiles`, `#profRow`).

## Save sync guard (old versions must not eat new progress)
- `GAME_BUILD` = build id number; `serialize()` stamps `W.stamp = {b: GAME_BUILD, t: savedAt}`. A save whose stamp is missing or `stamp.t !== savedAt` was last written by pre-guard code (`legacySaved`).
- Cloud `saves.version` (bigint) = GAME_BUILD; DB trigger `saves_build_guard` rejects updates with a lower version ("outdated game build"). Client then calls `needUpdate()` → saves locally and reloads.
- `fetchCloud` refuses (and reloads) when the cloud stamp is newer than this build; `syncCheck`/`onSignedIn` first check `version.json` (`newerBuildOut`). `cloudWins()` prefers a clean save over a legacy-written one, then the newer one.
