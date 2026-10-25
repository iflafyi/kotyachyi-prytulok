-- Snapshot of all public functions (generated). Source of truth is the live Supabase project.

CREATE OR REPLACE FUNCTION public.admin_announce(p_id uuid, p_secret text, p_kind text, p_title text, p_body text, p_hours integer DEFAULT 72)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare aid bigint;
begin
  perform admin_check(p_id, p_secret);
  insert into announcements (kind, title, body, until) values (case when p_kind = 'full' then 'full' else 'banner' end, left(coalesce(p_title,''), 120), left(coalesce(p_body,''), 1000),
    case when coalesce(p_hours, 0) > 0 then now() + make_interval(hours => least(p_hours, 24*60)) end) returning id into aid;
  return aid;
end $function$
;

CREATE OR REPLACE FUNCTION public.admin_announce_off(p_id uuid, p_secret text, p_ann bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin perform admin_check(p_id, p_secret); update announcements set active = false where id = p_ann; end $function$
;

CREATE OR REPLACE FUNCTION public.admin_backup_get(p_id uuid, p_secret text, p_player uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  perform admin_check(p_id, p_secret);
  select jsonb_build_object('state', b.state, 'at', extract(epoch from b.at)*1000, 'prev_state', b.prev_state, 'prev_at', extract(epoch from b.prev_at)*1000)
    into r from save_backups b where b.player_id = p_player;
  return r;
end $function$
;

CREATE OR REPLACE FUNCTION public.admin_check(p_id uuid, p_secret text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare nick text;
begin
  nick := trade_check(p_id, p_secret);
  if not exists (select 1 from admins where id = p_id) then raise exception 'not admin'; end if;
  return nick;
end $function$
;

CREATE OR REPLACE FUNCTION public.admin_event(p_id uuid, p_secret text, p_kind text, p_hours integer DEFAULT 24)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare eid bigint;
begin
  perform admin_check(p_id, p_secret);
  insert into game_events (kind, ends) values (p_kind, now() + make_interval(hours => greatest(1, least(coalesce(p_hours, 24), 24*14)))) returning id into eid;
  return eid;
end $function$
;

CREATE OR REPLACE FUNCTION public.admin_event_off(p_id uuid, p_secret text, p_event bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin perform admin_check(p_id, p_secret); update game_events set active = false where id = p_event; end $function$
;

CREATE OR REPLACE FUNCTION public.admin_gift(p_id uuid, p_secret text, p_to uuid, p_kind text, p_payload jsonb, p_msg text DEFAULT ''::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare nick text; n int;
begin
  nick := admin_check(p_id, p_secret);
  if p_kind not in ('coins','food','pet') then raise exception 'bad kind'; end if;
  insert into gifts (from_id, from_nick, to_id, kind, payload, msg)
    select p_id, nick, p.id, p_kind, p_payload, left(coalesce(p_msg, ''), 200) from players p where (p_to is null or p.id = p_to) and p.id <> p_id;
  get diagnostics n = row_count;
  return n;
end $function$
;

CREATE OR REPLACE FUNCTION public.admin_restore(p_id uuid, p_secret text, p_player uuid, p_state text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform admin_check(p_id, p_secret);
  insert into restores (player_id, state, at, taken) values (p_player, p_state, now(), false)
  on conflict (player_id) do update set state = excluded.state, at = now(), taken = false;
end $function$
;

CREATE OR REPLACE FUNCTION public.admin_stats(p_id uuid, p_secret text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  perform admin_check(p_id, p_secret);
  with pets as (
    select c->>'coat' coat from players p, jsonb_array_elements(case when jsonb_typeof(p.house->'cats') = 'array' then p.house->'cats' else '[]'::jsonb end) c
    union all
    select c->>'coat' from players p, jsonb_each(case when jsonb_typeof(p.house->'others') = 'object' then p.house->'others' else '{}'::jsonb end) o,
      jsonb_array_elements(case when jsonb_typeof(o.value->'cats') = 'array' then o.value->'cats' else '[]'::jsonb end) c
  )
  select jsonb_build_object(
    'players', (select count(*) from players),
    'online', (select count(*) from players where last_seen > now() - interval '2 minutes'),
    'today', (select count(*) from players where last_seen > now() - interval '1 day'),
    'week', (select count(*) from players where last_seen > now() - interval '7 days'),
    'new_week', (select count(*) from players where created_at > now() - interval '7 days'),
    'coins', (select coalesce(sum(coins), 0) from players),
    'pets', (select count(*) from pets),
    'msgs_today', (select count(*) from chat_msgs where at > now() - interval '1 day'),
    'gifts_today', (select count(*) from gifts where at > now() - interval '1 day'),
    'top', (select coalesce(jsonb_agg(jsonb_build_object('coat', coat, 'n', n)), '[]'::jsonb) from (select coat, count(*) n from pets where coat is not null group by coat order by n desc limit 12) t)
  ) into r;
  return r;
end $function$
;

CREATE OR REPLACE FUNCTION public.admin_world(p_id uuid, p_secret text, p_kind text, p_target bigint, p_hours integer, p_reward integer, p_title text DEFAULT ''::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare eid bigint;
begin
  perform admin_check(p_id, p_secret);
  update world_events set active = false where active and ends > now();
  insert into world_events (kind, title, target, reward, ends) values (p_kind, left(coalesce(p_title, ''), 80), greatest(10, p_target), greatest(0, least(p_reward, 1000000)),
    now() + make_interval(hours => greatest(1, least(coalesce(p_hours, 72), 24*14)))) returning id into eid;
  return eid;
end $function$
;

CREATE OR REPLACE FUNCTION public.admin_world_stats(p_id uuid, p_secret text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform admin_check(p_id, p_secret);
  return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'title', title, 'target', target, 'progress', progress, 'ends', extract(epoch from ends)*1000, 'active', active) order by id desc), '[]'::jsonb)
    from (select * from world_events order by id desc limit 5) t);
end $function$
;

CREATE OR REPLACE FUNCTION public.announce_list()
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('id', id, 'at', extract(epoch from at)*1000, 'kind', kind, 'title', title, 'body', body)
  from announcements where active and (until is null or until > now()) order by id desc limit 5;
$function$
;

CREATE OR REPLACE FUNCTION public.are_friends(x uuid, y uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from friends where status = 'ok' and ((a = x and b = y) or (a = y and b = x)));
$function$
;

CREATE OR REPLACE FUNCTION public.backup_save(p_id uuid, p_secret text, p_state text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  if octet_length(p_state) > 3000000 then raise exception 'too big'; end if;
  insert into save_backups (player_id, state, at) values (p_id, p_state, now())
  on conflict (player_id) do update set
    prev_state = case when save_backups.at < now() - interval '12 hours' then save_backups.state else save_backups.prev_state end,
    prev_at = case when save_backups.at < now() - interval '12 hours' then save_backups.at else save_backups.prev_at end,
    state = excluded.state, at = now();
end $function$
;

CREATE OR REPLACE FUNCTION public.chat_dm(p_id uuid, p_secret text, p_with uuid, p_after bigint DEFAULT 0)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  return query
  select jsonb_build_object('id', s.id, 'at', s.at, 'from', s.from_id, 'nick', s.from_nick, 'body', s.body, 'img', s.img_id)
  from (select * from chat_msgs where to_id is not null and ((from_id = p_id and to_id = p_with) or (from_id = p_with and to_id = p_id))
        and id > coalesce(p_after, 0) order by id desc limit 80) s
  order by s.id asc;
end $function$
;

CREATE OR REPLACE FUNCTION public.chat_global(p_after bigint DEFAULT 0)
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('id', s.id, 'at', s.at, 'from', s.from_id, 'nick', s.from_nick, 'body', s.body, 'img', s.img_id)
  from (select * from chat_msgs where to_id is null and id > coalesce(p_after, 0) order by id desc limit 80) s
  order by s.id asc;
$function$
;

CREATE OR REPLACE FUNCTION public.chat_img(p_id uuid, p_secret text, p_img bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d text;
begin
  select i.data into d from chat_imgs i where i.id = p_img and exists (select 1 from chat_msgs m where m.img_id = i.id and m.to_id is null);
  if d is not null then return d; end if;
  perform trade_check(p_id, p_secret);
  select i.data into d from chat_imgs i where i.id = p_img and exists (select 1 from chat_msgs m where m.img_id = i.id and (m.from_id = p_id or m.to_id = p_id));
  return d;
end $function$
;

CREATE OR REPLACE FUNCTION public.chat_react(p_id uuid, p_secret text, p_msg bigint, p_emoji text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  if p_emoji is not null and p_emoji not in ('❤️','😂','😮','😢','👍','🐾') then raise exception 'bad emoji'; end if;
  if not exists (select 1 from chat_msgs m where m.id = p_msg and (m.to_id is null or m.to_id = p_id or m.from_id = p_id)) then raise exception 'gone'; end if;
  insert into chat_reacts (msg_id, player_id, emoji) values (p_msg, p_id, coalesce(p_emoji, ''))
    on conflict (msg_id, player_id) do update set emoji = coalesce(p_emoji, ''), at = now();
end $function$
;

CREATE OR REPLACE FUNCTION public.chat_reacts_get(p_id uuid, p_ids bigint[])
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('msg', msg_id, 'emoji', emoji, 'n', count(*), 'mine', bool_or(player_id = p_id))
  from chat_reacts where msg_id = any(p_ids[1:200]) and emoji <> '' group by msg_id, emoji;
$function$
;

CREATE OR REPLACE FUNCTION public.chat_send(p_id uuid, p_secret text, p_to uuid, p_body text, p_img text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare nick text; b text := left(btrim(coalesce(p_body, '')), 500); iid bigint; mid bigint; mat timestamptz;
begin
  nick := trade_check(p_id, p_secret);
  if exists (select 1 from chat_msgs where from_id = p_id and at > now() - interval '1 second') then raise exception 'slow down'; end if;
  if b = '' and p_img is null then raise exception 'empty'; end if;
  if p_to is not null and not exists (select 1 from players where id = p_to) then raise exception 'no such player'; end if;
  if p_img is not null then
    if length(p_img) > 400000 or p_img !~ '^data:image/(jpeg|webp|png);base64,' then raise exception 'bad image'; end if;
    if (select count(*) from chat_imgs where owner = p_id and at > now() - interval '1 day') >= 40 then raise exception 'too many images'; end if;
    insert into chat_imgs (owner, data) values (p_id, p_img) returning id into iid;
  end if;
  insert into chat_msgs (from_id, from_nick, to_id, body, img_id) values (p_id, nick, p_to, b, iid) returning id, at into mid, mat;
  return jsonb_build_object('id', mid, 'at', mat);
end $function$
;

CREATE OR REPLACE FUNCTION public.chat_threads(p_id uuid, p_secret text)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  return query
  with m as (select c.*, case when c.from_id = p_id then c.to_id else c.from_id end as other
             from chat_msgs c where c.to_id is not null and (c.from_id = p_id or c.to_id = p_id)),
       l as (select distinct on (other) other, id, body, at, from_id, from_nick, img_id from m order by other, id desc)
  select jsonb_build_object('with', l.other, 'nick', coalesce(p.nickname, case when l.from_id <> p_id then l.from_nick else '?' end),
    'last_id', l.id, 'body', l.body, 'img', l.img_id is not null, 'at', l.at, 'mine', l.from_id = p_id,
    'online', coalesce(p.last_seen > now() - interval '2 minutes', false))
  from l left join players p on p.id = l.other
  order by l.id desc limit 50;
end $function$
;

CREATE OR REPLACE FUNCTION public.club_claim(p_id uuid, p_secret text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c clubs;
begin
  perform trade_check(p_id, p_secret);
  select k.* into c from clubs k join club_members m on m.club_id = k.id where m.player_id = p_id;
  if c.id is null then raise exception 'no club'; end if;
  if c.progress < c.target then raise exception 'not yet'; end if;
  insert into club_claims (club_id, week, player_id) values (c.id, c.week, p_id) on conflict do nothing;
  if not found then raise exception 'gone'; end if;
  return jsonb_build_object('lvl', club_lvl(c.bxp));
end $function$
;

CREATE OR REPLACE FUNCTION public.club_create(p_id uuid, p_secret text, p_name text, p_emblem text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare nick text; cid bigint; nm text := btrim(coalesce(p_name, ''));
begin
  nick := trade_check(p_id, p_secret);
  if exists (select 1 from club_members where player_id = p_id and club_id > 0) then raise exception 'already in club'; end if;
  if char_length(nm) < 2 or char_length(nm) > 24 then raise exception 'bad name'; end if;
  if exists (select 1 from clubs where active and lower(name) = lower(nm)) then raise exception 'name taken'; end if;
  insert into clubs (name, emblem, owner) values (nm, left(coalesce(p_emblem, '🐾'), 8), p_id) returning id into cid;
  insert into club_members (player_id, club_id, nick, role, joined_at, week, contrib) values (p_id, cid, nick, 'owner', now(), '', 0)
    on conflict (player_id) do update set club_id = excluded.club_id, nick = excluded.nick, role = 'owner', joined_at = now(), week = '', contrib = 0;
  perform club_roll(cid);
  return cid;
end $function$
;

CREATE OR REPLACE FUNCTION public.club_donate(p_id uuid, p_secret text, p_coins integer, p_pet jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cid bigint; nick text; x bigint := 0;
begin
  nick := trade_check(p_id, p_secret);
  select club_id into cid from club_members where player_id = p_id;
  if cid is null or cid <= 0 then raise exception 'no club'; end if;
  if coalesce(p_coins, 0) < 0 or coalesce(p_coins, 0) > 1000000 then raise exception 'bad amount'; end if;
  x := coalesce(p_coins, 0);
  if p_pet is not null then
    if octet_length(p_pet::text) > 2000 then raise exception 'too big'; end if;
    x := x + 500 * (1 + least(6, greatest(0, coalesce((p_pet->>'rar')::int, 0))));
    update clubs set pets = (case when jsonb_array_length(pets) >= 24 then pets - 0 else pets end) || jsonb_build_array(p_pet || jsonb_build_object('by', nick)) where id = cid;
  end if;
  update clubs set bank = bank + coalesce(p_coins, 0), bxp = bxp + x where id = cid;
  update club_members set total = total + x where player_id = p_id;
  return jsonb_build_object('lvl', (select club_lvl(bxp) from clubs where id = cid), 'bxp', (select bxp from clubs where id = cid));
end $function$
;

CREATE OR REPLACE FUNCTION public.club_get(p_id uuid, p_secret text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cid bigint; c clubs; r jsonb;
begin
  perform trade_check(p_id, p_secret);
  select club_id into cid from club_members where player_id = p_id;
  if cid is null or cid <= 0 then return null; end if;
  perform club_roll(cid);
  select * into c from clubs where id = cid;
  select jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem, 'owner', c.owner, 'week', c.week, 'goal', c.goal, 'target', c.target, 'progress', c.progress,
    'score', c.score, 'bank', c.bank, 'bxp', c.bxp, 'lvl', club_lvl(c.bxp), 'pets', c.pets,
    'claimed', exists (select 1 from club_claims k where k.club_id = c.id and k.week = c.week and k.player_id = p_id),
    'members', (select coalesce(jsonb_agg(jsonb_build_object('id', m.player_id, 'nick', m.nick, 'role', m.role, 'contrib', case when m.week = c.week then m.contrib else 0 end, 'total', m.total,
        'online', p.last_seen > now() - interval '2 minutes', 'seen_ago', extract(epoch from now() - p.last_seen)::int, 'level', p.level) order by m.contrib desc), '[]'::jsonb)
      from club_members m left join players p on p.id = m.player_id where m.club_id = c.id)) into r;
  return r;
end $function$
;

CREATE OR REPLACE FUNCTION public.club_goal_base(k text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case k when 'pet' then 300 when 'feed' then 200 when 'rescue' then 40 when 'visitor' then 40 when 'fish' then 40 when 'arena' then 25 else 200 end;
$function$
;

CREATE OR REPLACE FUNCTION public.club_goal_for(p_club bigint, p_week text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select (array['pet','feed','rescue','visitor','fish','arena'])[1 + abs(hashtext(p_week || ':' || p_club::text)) % 6];
$function$
;

CREATE OR REPLACE FUNCTION public.club_join(p_id uuid, p_secret text, p_club bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare nick text;
begin
  nick := trade_check(p_id, p_secret);
  if exists (select 1 from club_members where player_id = p_id and club_id > 0) then raise exception 'already in club'; end if;
  if not exists (select 1 from clubs where id = p_club and active) then raise exception 'gone'; end if;
  if (select count(*) from club_members where club_id = p_club) >= 10 then raise exception 'club full'; end if;
  perform club_roll(p_club);
  insert into club_members (player_id, club_id, nick, role, joined_at, week, contrib) values (p_id, p_club, nick, 'member', now(), week_id(), 0)
    on conflict (player_id) do update set club_id = excluded.club_id, nick = excluded.nick, role = 'member', joined_at = now(), week = week_id(), contrib = 0;
end $function$
;

CREATE OR REPLACE FUNCTION public.club_kick(p_id uuid, p_secret text, p_who uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cid bigint;
begin
  perform trade_check(p_id, p_secret);
  select club_id into cid from club_members where player_id = p_id and role = 'owner';
  if cid is null or cid <= 0 then raise exception 'not owner'; end if;
  update club_members set club_id = 0, role = 'member' where player_id = p_who and club_id = cid and player_id <> p_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.club_leave(p_id uuid, p_secret text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cid bigint; r text; nxt uuid;
begin
  perform trade_check(p_id, p_secret);
  select club_id, role into cid, r from club_members where player_id = p_id;
  if cid is null or cid <= 0 then return; end if;
  update club_members set club_id = 0, role = 'member' where player_id = p_id;
  if r = 'owner' then
    select player_id into nxt from club_members where club_id = cid order by joined_at limit 1;
    if nxt is null then update clubs set active = false where id = cid;
    else update clubs set owner = nxt where id = cid; update club_members set role = 'owner' where player_id = nxt; end if;
  end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.club_list()
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem, 'members', (select count(*) from club_members m where m.club_id = c.id),
    'score', c.score, 'lvl', club_lvl(c.bxp))
  from clubs c where c.active order by c.score desc, c.id limit 50;
$function$
;

CREATE OR REPLACE FUNCTION public.club_lvl(x bigint)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select least(10, (select count(*)::int from generate_series(1, 10) l where x >= 2500 * l * (l + 1)));
$function$
;

CREATE OR REPLACE FUNCTION public.club_msgs_get(p_id uuid, p_secret text, p_after bigint DEFAULT 0)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cid bigint;
begin
  perform trade_check(p_id, p_secret);
  select club_id into cid from club_members where player_id = p_id;
  if cid is null or cid <= 0 then return; end if;
  return query select x.j from (select jsonb_build_object('id', id, 'at', at, 'from', from_id, 'nick', nick, 'body', body) j, id from club_msgs
    where club_id = cid and id > coalesce(p_after, 0) and at > now() - interval '30 days' order by id desc limit 80) x order by x.id;
end $function$
;

CREATE OR REPLACE FUNCTION public.club_roll(p_club bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare w text := week_id(); n int; g text;
begin
  if exists (select 1 from clubs where id = p_club and week = w) then return; end if;
  select count(*) into n from club_members where club_id = p_club;
  g := club_goal_for(p_club, w);
  update clubs set week = w, goal = g, target = club_goal_base(g) * greatest(3, n), progress = 0 where id = p_club;
  update club_members set week = w, contrib = 0 where club_id = p_club and week <> w;
end $function$
;

CREATE OR REPLACE FUNCTION public.club_say(p_id uuid, p_secret text, p_body text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cid bigint; nick text; mid bigint;
begin
  nick := trade_check(p_id, p_secret);
  select club_id into cid from club_members where player_id = p_id;
  if cid is null or cid <= 0 then raise exception 'no club'; end if;
  if char_length(btrim(coalesce(p_body, ''))) = 0 then raise exception 'empty'; end if;
  if (select count(*) from club_msgs where from_id = p_id and at > now() - interval '1 minute') >= 12 then raise exception 'too many'; end if;
  insert into club_msgs (club_id, from_id, nick, body) values (cid, p_id, nick, left(p_body, 300)) returning id into mid;
  return mid;
end $function$
;

CREATE OR REPLACE FUNCTION public.coexp_cancel(p_id uuid, p_secret text, p_x bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  update coexps set status = 'cancel' where id = p_x and (host = p_id or guest = p_id) and status = 'open';
end $function$
;

CREATE OR REPLACE FUNCTION public.coexp_create(p_id uuid, p_secret text, p_to uuid, p_kind text, p_ms bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare nick text; tn text; xid bigint;
begin
  nick := trade_check(p_id, p_secret);
  if not are_friends(p_id, p_to) then raise exception 'not friends'; end if;
  select nickname into tn from players where id = p_to;
  if (select count(*) from coexps where host = p_id and status = 'open' and created > now() - interval '9 hours') >= 3 then raise exception 'too many'; end if;
  insert into coexps (kind, ms, host, host_nick, guest, guest_nick) values (left(p_kind, 4), least(greatest(p_ms, 60000), 9*3600000), p_id, nick, p_to, tn) returning id into xid;
  return xid;
end $function$
;

CREATE OR REPLACE FUNCTION public.coexp_join(p_id uuid, p_secret text, p_x bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare x coexps;
begin
  perform trade_check(p_id, p_secret);
  update coexps set status = 'go', ends = greatest(now() + interval '1 minute', created + make_interval(secs => ms * 0.7 / 1000.0))
    where id = p_x and guest = p_id and status = 'open' and now() < created + make_interval(secs => ms * 0.6 / 1000.0) returning * into x;
  if x.id is null then raise exception 'gone'; end if;
  return jsonb_build_object('kind', x.kind, 'ends', extract(epoch from x.ends)*1000, 'host_nick', x.host_nick);
end $function$
;

CREATE OR REPLACE FUNCTION public.coexp_list(p_id uuid, p_secret text)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  return query select jsonb_build_object('id', x.id, 'kind', x.kind, 'ms', x.ms, 'created', extract(epoch from x.created)*1000, 'host', x.host, 'host_nick', x.host_nick,
      'guest', x.guest, 'guest_nick', x.guest_nick, 'status', x.status, 'ends', extract(epoch from x.ends)*1000, 'mine', x.host = p_id)
    from coexps x where (x.host = p_id or x.guest = p_id) and x.created > now() - interval '10 hours' and x.status <> 'cancel' order by x.id desc limit 20;
end $function$
;

CREATE OR REPLACE FUNCTION public.contest_claim(p_id uuid, p_secret text, p_kind text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pw text := prev_week_id(); pl int;
begin
  perform trade_check(p_id, p_secret);
  select t.place into pl from (select e.player_id, row_number() over (order by v.n desc, e.id) place, v.n from contest_entries e
      cross join lateral (select count(*)::int n from contest_votes x where x.entry_id = e.id and x.active) v where e.week = pw and e.kind = p_kind) t
    where t.player_id = p_id and t.place <= 3 and t.n > 0;
  if pl is null then raise exception 'gone'; end if;
  insert into contest_claims (week, kind, player_id, place) values (pw, p_kind, p_id, pl) on conflict do nothing;
  if not found then raise exception 'gone'; end if;
  return pl;
end $function$
;

CREATE OR REPLACE FUNCTION public.contest_enter(p_id uuid, p_secret text, p_kind text, p_data jsonb, p_img text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare nick text; eid bigint; w text := week_id();
begin
  nick := trade_check(p_id, p_secret);
  if p_kind not in ('pet','room') then raise exception 'bad kind'; end if;
  if octet_length(coalesce(p_data, '{}'::jsonb)::text) > 3000 then raise exception 'too big'; end if;
  if p_img is not null and octet_length(p_img) > 400000 then raise exception 'too big'; end if;
  if p_kind = 'room' and p_img is null then raise exception 'no image'; end if;
  insert into contest_entries (week, kind, player_id, nick, data, img) values (w, p_kind, p_id, nick, coalesce(p_data, '{}'::jsonb), p_img)
    on conflict (week, kind, player_id) do update set data = excluded.data, img = excluded.img, nick = excluded.nick, at = now() returning id into eid;
  update contest_votes set active = false where week = w and kind = p_kind and entry_id = eid;
  return eid;
end $function$
;

CREATE OR REPLACE FUNCTION public.contest_img(p_entry bigint)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select img from contest_entries where id = p_entry;
$function$
;

CREATE OR REPLACE FUNCTION public.contest_list(p_id uuid, p_secret text, p_kind text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare w text := week_id(); pw text := prev_week_id();
begin
  perform trade_check(p_id, p_secret);
  return jsonb_build_object(
    'week', w,
    'entries', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'from', e.player_id, 'nick', e.nick, 'data', e.data, 'votes', v.n, 'mine', e.player_id = p_id) order by v.n desc, e.id), '[]'::jsonb)
      from contest_entries e cross join lateral (select count(*)::int n from contest_votes x where x.entry_id = e.id and x.active) v where e.week = w and e.kind = p_kind),
    'myvotes', (select coalesce(jsonb_agg(entry_id), '[]'::jsonb) from contest_votes where week = w and kind = p_kind and voter = p_id and active),
    'last', (select coalesce(jsonb_agg(t.j order by t.n desc, t.id), '[]'::jsonb) from (select e.id, v.n, jsonb_build_object('id', e.id, 'from', e.player_id, 'nick', e.nick, 'data', e.data, 'votes', v.n) j
      from contest_entries e cross join lateral (select count(*)::int n from contest_votes x where x.entry_id = e.id and x.active) v where e.week = pw and e.kind = p_kind order by v.n desc, e.id limit 3) t),
    'claimed', exists (select 1 from contest_claims where week = pw and kind = p_kind and player_id = p_id));
end $function$
;

CREATE OR REPLACE FUNCTION public.contest_vote(p_id uuid, p_secret text, p_entry bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e contest_entries; w text := week_id(); cur boolean;
begin
  perform trade_check(p_id, p_secret);
  select * into e from contest_entries where id = p_entry and week = w;
  if e.id is null then raise exception 'gone'; end if;
  if e.player_id = p_id then raise exception 'own entry'; end if;
  select active into cur from contest_votes where week = w and kind = e.kind and voter = p_id and entry_id = e.id;
  if cur then update contest_votes set active = false where week = w and kind = e.kind and voter = p_id and entry_id = e.id; return false; end if;
  if (select count(*) from contest_votes where week = w and kind = e.kind and voter = p_id and active) >= 3 then raise exception 'too many'; end if;
  insert into contest_votes (week, kind, voter, entry_id, active) values (w, e.kind, p_id, e.id, true) on conflict (week, kind, voter, entry_id) do update set active = true;
  return true;
end $function$
;

CREATE OR REPLACE FUNCTION public.contrib_push(p_id uuid, p_secret text, p_c jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k text; v int; cid bigint; g text; e world_events;
begin
  perform trade_check(p_id, p_secret);
  select club_id into cid from club_members where player_id = p_id;
  if cid is not null and cid > 0 then perform club_roll(cid); select goal into g from clubs where id = cid; end if;
  select * into e from world_events where active and starts <= now() and ends > now() order by id desc limit 1;
  for k, v in select key, least(500, greatest(0, (value)::text::int)) from jsonb_each(coalesce(p_c, '{}'::jsonb)) where key in ('pet','feed','rescue','visitor','fish','arena','groom','exp') loop
    if v <= 0 then continue; end if;
    if g is not null and k = g then
      update clubs set progress = progress + v, score = score + v where id = cid;
      update club_members set contrib = contrib + v, total = total + v, week = week_id() where player_id = p_id;
    end if;
    if e.id is not null and k = e.kind then
      update world_events set progress = progress + v where id = e.id;
      insert into world_contrib (event_id, player_id, n) values (e.id, p_id, v) on conflict (event_id, player_id) do update set n = world_contrib.n + v;
    end if;
  end loop;
  return jsonb_build_object('ok', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.delete_player(p_id uuid, p_secret text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  delete from players p using player_secrets s
  where p.id = p_id and s.id = p.id and s.secret_hash = encode(sha256(convert_to(coalesce(p_secret,''), 'UTF8')), 'hex');
end $function$
;

CREATE OR REPLACE FUNCTION public.duel_accept(p_id uuid, p_secret text, p_duel bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d duels;
begin
  perform trade_check(p_id, p_secret);
  update duels set status = 'accepted', acc_at = now() where id = p_duel and b = p_id and status = 'open' and at > now() - interval '30 minutes' returning * into d;
  if d.id is null then raise exception 'gone'; end if;
  return jsonb_build_object('code', d.code, 'game', d.game, 'stake', d.stake, 'a_nick', d.a_nick);
end $function$
;

CREATE OR REPLACE FUNCTION public.duel_cancel(p_id uuid, p_secret text, p_duel bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st text;
begin
  perform trade_check(p_id, p_secret);
  update duels set status = 'cancel', claimed_b = true where id = p_duel and (a = p_id or b = p_id) and status = 'open' returning status into st;
  if st is null then raise exception 'gone'; end if;
  return st;
end $function$
;

CREATE OR REPLACE FUNCTION public.duel_claim(p_id uuid, p_secret text, p_duel bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d duels;
begin
  perform trade_check(p_id, p_secret);
  update duels set status = 'void' where id = p_duel and ((status = 'open' and at < now() - interval '30 minutes') or (status = 'accepted' and acc_at < now() - interval '20 minutes'));
  select * into d from duels where id = p_duel and (a = p_id or b = p_id);
  if d.id is null then raise exception 'gone'; end if;
  if (d.a = p_id and d.claimed_a) or (d.b = p_id and d.claimed_b) then return jsonb_build_object('kind', 'none'); end if;
  if d.status = 'done' then
    if d.a = p_id then update duels set claimed_a = true where id = d.id; else update duels set claimed_b = true where id = d.id; end if;
    return jsonb_build_object('kind', case when d.winner = p_id then 'win' else 'lose' end, 'amount', case when d.winner = p_id then d.stake * 2 else 0 end);
  end if;
  if d.status in ('void','cancel') then
    if d.a = p_id then update duels set claimed_a = true where id = d.id; else update duels set claimed_b = true where id = d.id; end if;
    if d.b = p_id and d.acc_at is null then return jsonb_build_object('kind', 'none'); end if;
    return jsonb_build_object('kind', 'refund', 'amount', d.stake);
  end if;
  return jsonb_build_object('kind', 'wait');
end $function$
;

CREATE OR REPLACE FUNCTION public.duel_create(p_id uuid, p_secret text, p_to uuid, p_game text, p_stake integer, p_code text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare nick text; tn text; did bigint;
begin
  nick := trade_check(p_id, p_secret);
  if p_to = p_id then raise exception 'self'; end if;
  select nickname into tn from players where id = p_to; if tn is null then raise exception 'no such player'; end if;
  if p_stake < 0 or p_stake > 50000 then raise exception 'bad stake'; end if;
  if (select count(*) from duels where a = p_id and status = 'open' and at > now() - interval '30 minutes') >= 3 then raise exception 'too many'; end if;
  insert into duels (a, a_nick, b, b_nick, game, stake, code) values (p_id, nick, p_to, tn, left(p_game, 10), p_stake, upper(left(p_code, 4))) returning id into did;
  return did;
end $function$
;

CREATE OR REPLACE FUNCTION public.duel_list(p_id uuid, p_secret text)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  update duels set status = 'void' where (a = p_id or b = p_id) and ((status = 'open' and at < now() - interval '30 minutes') or (status = 'accepted' and acc_at < now() - interval '20 minutes'));
  return query select jsonb_build_object('id', id, 'at', extract(epoch from at)*1000, 'a', a, 'a_nick', a_nick, 'b', b, 'b_nick', b_nick, 'game', game, 'stake', stake, 'code', code,
      'status', status, 'winner', winner, 'mine', a = p_id, 'claimed', case when a = p_id then claimed_a else claimed_b end)
    from duels where (a = p_id or b = p_id) and at > now() - interval '2 days'
      and (status in ('open','accepted') or (status in ('done','void') and not (case when a = p_id then claimed_a else claimed_b end)))
    order by id desc limit 20;
end $function$
;

CREATE OR REPLACE FUNCTION public.duel_result(p_id uuid, p_secret text, p_duel bigint, p_winner uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  update duels set status = 'done', winner = p_winner where id = p_duel and a = p_id and status = 'accepted' and (p_winner = a or p_winner = b);
end $function$
;

CREATE OR REPLACE FUNCTION public.events_active()
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('id', id, 'kind', kind, 'starts', extract(epoch from starts)*1000, 'ends', extract(epoch from ends)*1000)
  from game_events where active and starts <= now() and ends > now() order by id;
$function$
;

CREATE OR REPLACE FUNCTION public.feed_list(p_id uuid, p_secret text)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  return query
    select jsonb_build_object('id', e.id, 'at', extract(epoch from e.at)*1000, 'from', e.player_id, 'nick', e.nick, 'kind', e.kind, 'data', e.data, 'mine', e.player_id = p_id)
    from feed_events e
    where e.at > now() - interval '7 days' and (e.player_id = p_id or are_friends(p_id, e.player_id))
    order by e.id desc limit 60;
end $function$
;

CREATE OR REPLACE FUNCTION public.feed_post(p_id uuid, p_secret text, p_kind text, p_data jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare nick text;
begin
  nick := trade_check(p_id, p_secret);
  if octet_length(coalesce(p_data, '{}'::jsonb)::text) > 1000 then raise exception 'too big'; end if;
  if (select count(*) from feed_events where player_id = p_id and at > now() - interval '1 day') >= 40 then return; end if;
  insert into feed_events (player_id, nick, kind, data) values (p_id, nick, left(p_kind, 20), coalesce(p_data, '{}'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.friend_answer(p_id uuid, p_secret text, p_from uuid, p_ok boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  update friends set status = case when p_ok then 'ok' else 'no' end, at = now() where a = p_from and b = p_id and status = 'pending';
end $function$
;

CREATE OR REPLACE FUNCTION public.friend_list(p_id uuid, p_secret text)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  return query
    select jsonb_build_object('id', p.id, 'nick', p.nickname, 'level', p.level, 'coins', p.coins, 'cats', p.cats,
      'online', p.last_seen > now() - interval '2 minutes', 'seen_ago', extract(epoch from now() - p.last_seen)::int,
      'status', case when f.status = 'ok' then 'ok' when f.a = p_id then 'out' else 'in' end)
    from friends f join players p on p.id = case when f.a = p_id then f.b else f.a end
    where (f.a = p_id or f.b = p_id) and (f.status = 'ok' or f.status = 'pending')
    order by (f.status = 'ok') desc, p.last_seen desc;
end $function$
;

CREATE OR REPLACE FUNCTION public.friend_remove(p_id uuid, p_secret text, p_other uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  update friends set status = 'removed', at = now() where (a = p_id and b = p_other) or (a = p_other and b = p_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.friend_request(p_id uuid, p_secret text, p_to uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  if p_to = p_id then raise exception 'self'; end if;
  if not exists (select 1 from players where id = p_to) then raise exception 'no such player'; end if;
  if are_friends(p_id, p_to) then return 'ok'; end if;
  if exists (select 1 from friends where a = p_to and b = p_id and status = 'pending') then
    update friends set status = 'ok', at = now() where a = p_to and b = p_id; return 'ok';
  end if;
  if (select count(*) from friends where a = p_id and status = 'pending' and at > now() - interval '1 day') >= 30 then raise exception 'too many'; end if;
  insert into friends (a, b, status, at) values (p_id, p_to, 'pending', now())
    on conflict (a, b) do update set status = 'pending', at = now();
  return 'pending';
end $function$
;

CREATE OR REPLACE FUNCTION public.gift_list(p_id uuid, p_secret text)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  return query
  select jsonb_build_object('id', g.id, 'at', g.at, 'from', g.from_id, 'nick', g.from_nick, 'kind', g.kind, 'payload', g.payload, 'msg', g.msg)
  from gifts g where g.to_id = p_id and g.status = 'sent' order by g.id desc limit 50;
end $function$
;

CREATE OR REPLACE FUNCTION public.gift_send(p_id uuid, p_secret text, p_to uuid, p_kind text, p_payload jsonb, p_msg text DEFAULT ''::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare nick text; gid bigint;
begin
  nick := trade_check(p_id, p_secret);
  if p_to = p_id then raise exception 'self gift'; end if;
  if not exists (select 1 from players where id = p_to) then raise exception 'no such player'; end if;
  if p_kind not in ('coins','food','pet') then raise exception 'bad kind'; end if;
  if octet_length(p_payload::text) > 4000 then raise exception 'too big'; end if;
  if (select count(*) from gifts where from_id = p_id and at > now() - interval '1 day') >= 30 then raise exception 'too many gifts'; end if;
  insert into gifts (from_id, from_nick, to_id, kind, payload, msg) values (p_id, nick, p_to, p_kind, p_payload, left(coalesce(p_msg, ''), 200)) returning id into gid;
  return gid;
end $function$
;

CREATE OR REPLACE FUNCTION public.gift_take(p_id uuid, p_secret text, p_gift bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r gifts;
begin
  perform trade_check(p_id, p_secret);
  update gifts set status = 'taken', taken_at = now() where id = p_gift and to_id = p_id and status = 'sent' returning * into r;
  if r.id is null then raise exception 'gift gone'; end if;
  return jsonb_build_object('kind', r.kind, 'payload', r.payload, 'nick', r.from_nick);
end $function$
;

CREATE OR REPLACE FUNCTION public.help_inbox(p_id uuid, p_secret text)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  return query
    with c as (update visit_helps set claimed = true where to_id = p_id and not claimed returning id, from_id, from_nick, kind, sp)
    select jsonb_build_object('id', id, 'from', from_id, 'nick', from_nick, 'kind', kind, 'sp', sp) from c;
end $function$
;

CREATE OR REPLACE FUNCTION public.help_today(p_id uuid, p_secret text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  return jsonb_build_object('left', greatest(0, 6 - (select count(*) from visit_helps where from_id = p_id and at > now() - interval '1 day')),
    'done', coalesce((select jsonb_agg(to_id::text || ':' || kind) from visit_helps where from_id = p_id and at > now() - interval '20 hours'), '[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.leaderboard(p_sort text DEFAULT 'coins'::text, p_limit integer DEFAULT 100)
 RETURNS TABLE(id uuid, nickname text, coins bigint, cats integer, collection integer, level integer, online boolean, seen_ago integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.id, p.nickname, p.coins, p.cats, p.collection, p.level,
         p.last_seen > now() - interval '2 minutes',
         extract(epoch from now() - p.last_seen)::int
  from players p
  order by case p_sort when 'collection' then p.collection when 'cats' then p.cats when 'level' then p.level end desc nulls last,
           p.coins desc
  limit least(greatest(coalesce(p_limit, 100), 1), 200);
$function$
;

CREATE OR REPLACE FUNCTION public.lend_cancel(p_id uuid, p_secret text, p_lend bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st text;
begin
  perform trade_check(p_id, p_secret);
  update lends set status = case when owner = p_id and status = 'sent' then 'cancel' else 'back' end, until = case when to_id = p_id then now() else until end
    where id = p_lend and ((owner = p_id and status = 'sent') or (to_id = p_id and status in ('sent','active'))) returning status into st;
  if st is null then raise exception 'gone'; end if;
  return st;
end $function$
;

CREATE OR REPLACE FUNCTION public.lend_list(p_id uuid, p_secret text)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  return query
    select jsonb_build_object('id', l.id, 'owner', l.owner, 'owner_nick', l.owner_nick, 'to', l.to_id, 'to_nick', l.to_nick, 'pet', l.pet,
      'until', extract(epoch from l.until)*1000, 'status', l.status, 'mine', l.owner = p_id)
    from lends l where (l.owner = p_id or l.to_id = p_id) and l.until > now() and l.status in ('sent','active') order by l.id desc limit 20;
end $function$
;

CREATE OR REPLACE FUNCTION public.lend_send(p_id uuid, p_secret text, p_to uuid, p_pet jsonb, p_hours integer)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare nick text; tnick text; lid bigint;
begin
  nick := trade_check(p_id, p_secret);
  if not are_friends(p_id, p_to) then raise exception 'not friends'; end if;
  if octet_length(p_pet::text) > 4000 then raise exception 'too big'; end if;
  select nickname into tnick from players where id = p_to;
  if (select count(*) from lends where owner = p_id and status in ('sent','active') and until > now()) >= 3 then raise exception 'too many'; end if;
  insert into lends (owner, owner_nick, to_id, to_nick, pet, until) values (p_id, nick, p_to, tnick, p_pet, now() + make_interval(hours => greatest(1, least(coalesce(p_hours, 24), 48)))) returning id into lid;
  return lid;
end $function$
;

CREATE OR REPLACE FUNCTION public.lend_status(p_id uuid, p_secret text, p_ids bigint[])
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  return query select jsonb_build_object('id', id, 'status', status, 'until', extract(epoch from until)*1000) from lends where id = any(p_ids) and (owner = p_id or to_id = p_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.lend_take(p_id uuid, p_secret text, p_lend bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l lends;
begin
  perform trade_check(p_id, p_secret);
  update lends set status = 'active' where id = p_lend and to_id = p_id and status = 'sent' and until > now() returning * into l;
  if l.id is null then raise exception 'gone'; end if;
  return jsonb_build_object('pet', l.pet, 'until', extract(epoch from l.until)*1000, 'owner', l.owner, 'owner_nick', l.owner_nick);
end $function$
;

CREATE OR REPLACE FUNCTION public.player_house(p_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('id', id, 'nickname', nickname, 'level', level, 'coins', coins, 'cats', cats,
    'collection', collection, 'house', house,
    'online', last_seen > now() - interval '2 minutes',
    'seen_ago', extract(epoch from now() - last_seen)::int)
  from players where id = p_id;
$function$
;

CREATE OR REPLACE FUNCTION public.prev_week_id()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$ select to_char((now() - interval '7 days') at time zone 'Europe/Warsaw', 'IYYY-IW'); $function$
;

CREATE OR REPLACE FUNCTION public.req_cancel(p_id uuid, p_secret text, p_req bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  update help_reqs set status = 'cancel' where id = p_req and player_id = p_id and status = 'open';
end $function$
;

CREATE OR REPLACE FUNCTION public.req_create(p_id uuid, p_secret text, p_kind text, p_amount integer, p_sp text, p_rar integer, p_note text DEFAULT ''::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare nick text; rid bigint;
begin
  nick := trade_check(p_id, p_secret);
  if p_kind not in ('food','coins','pet') then raise exception 'bad kind'; end if;
  if exists (select 1 from help_reqs where player_id = p_id and status = 'open') then raise exception 'already open'; end if;
  if p_kind = 'food' and (p_amount < 1 or p_amount > 200) then raise exception 'bad amount'; end if;
  if p_kind = 'coins' and (p_amount < 1 or p_amount > 20000) then raise exception 'bad amount'; end if;
  if p_kind = 'pet' and (p_rar is null or p_rar < 0 or p_rar > 4) then raise exception 'bad rar'; end if;
  insert into help_reqs (player_id, nick, kind, amount, sp, rar, note) values (p_id, nick, p_kind, case when p_kind = 'pet' then 0 else p_amount end,
    case when p_kind = 'pet' then coalesce(p_sp, 'cat') end, case when p_kind = 'pet' then p_rar end, left(coalesce(p_note, ''), 120)) returning id into rid;
  return rid;
end $function$
;

CREATE OR REPLACE FUNCTION public.req_fill(p_id uuid, p_secret text, p_req bigint, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare nick text; r help_reqs;
begin
  nick := trade_check(p_id, p_secret);
  if octet_length(coalesce(p_payload, '{}'::jsonb)::text) > 4000 then raise exception 'too big'; end if;
  update help_reqs set status = 'done', helper_id = p_id, helper_nick = nick, payload = p_payload, done_at = now()
    where id = p_req and status = 'open' and player_id <> p_id and are_friends(p_id, player_id) returning * into r;
  if r.id is null then raise exception 'gone'; end if;
  return jsonb_build_object('kind', r.kind, 'amount', r.amount, 'nick', r.nick, 'to', r.player_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.req_list(p_id uuid, p_secret text)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform trade_check(p_id, p_secret);
  return query
    select jsonb_build_object('id', r.id, 'at', extract(epoch from r.at)*1000, 'from', r.player_id, 'nick', r.nick, 'kind', r.kind, 'amount', r.amount, 'sp', r.sp, 'rar', r.rar,
      'note', r.note, 'status', r.status, 'helper', r.helper_nick, 'payload', r.payload, 'claimed', r.claimed, 'mine', r.player_id = p_id)
    from help_reqs r
    where (r.player_id = p_id and (r.status = 'open' or (r.status = 'done' and not r.claimed)))
       or (r.status = 'open' and r.at > now() - interval '3 days' and are_friends(p_id, r.player_id))
    order by r.id desc limit 40;
end $function$
;

CREATE OR REPLACE FUNCTION public.req_take(p_id uuid, p_secret text, p_req bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r help_reqs;
begin
  perform trade_check(p_id, p_secret);
  update help_reqs set claimed = true where id = p_req and player_id = p_id and status = 'done' and not claimed returning * into r;
  if r.id is null then raise exception 'gone'; end if;
  return jsonb_build_object('kind', r.kind, 'amount', r.amount, 'payload', r.payload, 'nick', r.helper_nick);
end $function$
;

CREATE OR REPLACE FUNCTION public.restore_check(p_id uuid, p_secret text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st text;
begin
  perform trade_check(p_id, p_secret);
  update restores set taken = true where player_id = p_id and not taken returning state into st;
  return st;
end $function$
;

CREATE OR REPLACE FUNCTION public.save_player(p_id uuid, p_secret text, p_nickname text, p_coins bigint, p_cats integer, p_collection integer, p_level integer, p_house jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  h    text;
  old  text;
  nick text := left(btrim(coalesce(p_nickname, '')), 20);
begin
  if p_secret is null or length(p_secret) < 24 then raise exception 'bad secret'; end if;
  if nick = '' then raise exception 'empty nickname'; end if;
  if p_house is not null and octet_length(p_house::text) > 200000 then raise exception 'house too big'; end if;
  h := encode(sha256(convert_to(p_secret, 'UTF8')), 'hex');
  select secret_hash into old from player_secrets where id = p_id;
  if old is not null and old <> h then raise exception 'not your player'; end if;
  insert into players (id, nickname, coins, cats, collection, level, house, last_seen)
  values (p_id, nick, greatest(coalesce(p_coins,0),0), greatest(coalesce(p_cats,0),0), greatest(coalesce(p_collection,0),0), greatest(coalesce(p_level,1),1), p_house, now())
  on conflict (id) do update set
    nickname = excluded.nickname, coins = excluded.coins, cats = excluded.cats,
    collection = excluded.collection, level = excluded.level,
    house = coalesce(excluded.house, players.house), last_seen = now();
  if old is null then insert into player_secrets (id, secret_hash) values (p_id, h); end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.trade_cancel(p_id uuid, p_secret text, p_trade uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare res jsonb;
begin
  perform trade_check(p_id, p_secret);
  update trades set status = 'cancelled' where id = p_trade and seller = p_id and status = 'open' returning offer into res;
  if res is null then raise exception 'trade gone'; end if;
  return res;
end $function$
;

CREATE OR REPLACE FUNCTION public.trade_check(p_id uuid, p_secret text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare nick text;
begin
  select p.nickname into nick from players p join player_secrets s on s.id = p.id
  where p.id = p_id and s.secret_hash = encode(sha256(convert_to(coalesce(p_secret,''), 'UTF8')), 'hex');
  if nick is null then raise exception 'not your player'; end if;
  return nick;
end $function$
;

CREATE OR REPLACE FUNCTION public.trade_close(p_id uuid, p_secret text, p_trade uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare res jsonb;
begin
  perform trade_check(p_id, p_secret);
  update trades set status = 'closed' where id = p_trade and seller = p_id and status = 'taken' returning paid into res;
  if res is null then raise exception 'trade gone'; end if;
  return res;
end $function$
;

CREATE OR REPLACE FUNCTION public.trade_create(p_id uuid, p_secret text, p_offer jsonb, p_want jsonb, p_to uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare nick text; tid uuid;
begin
  nick := trade_check(p_id, p_secret);
  if octet_length(p_offer::text) > 4000 or octet_length(p_want::text) > 1000 then raise exception 'too big'; end if;
  if (select count(*) from trades where seller = p_id and status = 'open') >= 5 then raise exception 'too many trades'; end if;
  insert into trades (seller, seller_nick, to_player, offer, want) values (p_id, nick, p_to, p_offer, p_want) returning id into tid;
  return tid;
end $function$
;

CREATE OR REPLACE FUNCTION public.trade_list(p_id uuid)
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('id', t.id, 'seller', t.seller, 'seller_nick', t.seller_nick, 'to_player', t.to_player,
    'offer', t.offer, 'want', t.want, 'status', t.status, 'buyer_nick', t.buyer_nick, 'mine', t.seller = p_id,
    'age', extract(epoch from now() - t.created_at)::int)
  from trades t
  where (t.status = 'open' and (t.to_player is null or t.to_player = p_id or t.seller = p_id))
     or (t.seller = p_id and t.status = 'taken')
  order by t.created_at desc
  limit 120;
$function$
;

CREATE OR REPLACE FUNCTION public.trade_take(p_id uuid, p_secret text, p_trade uuid, p_paid jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare nick text; res jsonb;
begin
  nick := trade_check(p_id, p_secret);
  if octet_length(coalesce(p_paid, '{}'::jsonb)::text) > 4000 then raise exception 'too big'; end if;
  update trades set status = 'taken', buyer = p_id, buyer_nick = nick, paid = p_paid, taken_at = now()
  where id = p_trade and status = 'open' and seller <> p_id and (to_player is null or to_player = p_id)
  returning offer into res;
  if res is null then raise exception 'trade gone'; end if;
  return res;
end $function$
;

CREATE OR REPLACE FUNCTION public.visit_help(p_id uuid, p_secret text, p_to uuid, p_kind text, p_sp text DEFAULT 'cat'::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare nick text; left_today int;
begin
  nick := trade_check(p_id, p_secret);
  if p_to = p_id then raise exception 'self'; end if;
  if p_kind not in ('feed','pet') then raise exception 'bad kind'; end if;
  if not exists (select 1 from players where id = p_to) then raise exception 'no such player'; end if;
  if exists (select 1 from visit_helps where from_id = p_id and to_id = p_to and kind = p_kind and at > now() - interval '20 hours') then raise exception 'already helped'; end if;
  left_today := 6 - (select count(*) from visit_helps where from_id = p_id and at > now() - interval '1 day');
  if left_today <= 0 then raise exception 'too many'; end if;
  insert into visit_helps (from_id, from_nick, to_id, kind, sp) values (p_id, nick, p_to, p_kind, coalesce(p_sp, 'cat'));
  return left_today - 1;
end $function$
;

CREATE OR REPLACE FUNCTION public.week_id()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$ select to_char(now() at time zone 'Europe/Warsaw', 'IYYY-IW'); $function$
;

CREATE OR REPLACE FUNCTION public.world_claim(p_id uuid, p_secret text, p_event bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rw int;
begin
  perform trade_check(p_id, p_secret);
  update world_contrib w set claimed = true from world_events e
    where w.event_id = p_event and w.player_id = p_id and not w.claimed and w.n > 0 and e.id = w.event_id and e.progress >= e.target returning e.reward into rw;
  if rw is null then raise exception 'gone'; end if;
  return rw;
end $function$
;

CREATE OR REPLACE FUNCTION public.world_get(p_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e world_events; n int; k text; r jsonb;
begin
  select * into e from world_events where active and starts <= now() and ends > now() order by id desc limit 1;
  if e.id is null and not exists (select 1 from world_events where starts > now() - interval '4 days') then
    select greatest(5, count(*)) into n from players where last_seen > now() - interval '7 days';
    k := (array['feed','pet','rescue','visitor'])[1 + (extract(week from now())::int % 4)];
    insert into world_events (kind, target, reward, ends) values (k, (case k when 'feed' then 300 when 'pet' then 450 when 'rescue' then 60 else 60 end) * n, 3000, now() + interval '3 days') returning * into e;
  end if;
  if e.id is null then return null; end if;
  select jsonb_build_object('id', e.id, 'kind', e.kind, 'title', e.title, 'target', e.target, 'progress', e.progress, 'reward', e.reward, 'ends', extract(epoch from e.ends)*1000,
    'mine', coalesce((select w.n from world_contrib w where w.event_id = e.id and w.player_id = p_id), 0),
    'claimed', coalesce((select w.claimed from world_contrib w where w.event_id = e.id and w.player_id = p_id), false)) into r;
  return r;
end $function$
;
