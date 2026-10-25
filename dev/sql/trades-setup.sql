-- Котячий притулок: торгівля улюбленцями між гравцями.
create table if not exists public.trades (
  id          uuid primary key default gen_random_uuid(),
  seller      uuid not null references public.players(id) on delete cascade,
  seller_nick text not null,
  to_player   uuid,
  offer       jsonb not null,
  want        jsonb not null,
  status      text not null default 'open' check (status in ('open','taken','closed','cancelled')),
  buyer       uuid,
  buyer_nick  text,
  paid        jsonb,
  created_at  timestamptz not null default now(),
  taken_at    timestamptz
);
create index if not exists trades_status_idx on public.trades (status, created_at desc);
create index if not exists trades_seller_idx on public.trades (seller);
alter table public.trades enable row level security;

create or replace function public.trade_check(p_id uuid, p_secret text) returns text
language plpgsql stable security definer set search_path = public as $$
declare nick text;
begin
  select p.nickname into nick from players p join player_secrets s on s.id = p.id
  where p.id = p_id and s.secret_hash = encode(sha256(convert_to(coalesce(p_secret,''), 'UTF8')), 'hex');
  if nick is null then raise exception 'not your player'; end if;
  return nick;
end $$;

create or replace function public.trade_create(p_id uuid, p_secret text, p_offer jsonb, p_want jsonb, p_to uuid default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare nick text; tid uuid;
begin
  nick := trade_check(p_id, p_secret);
  if octet_length(p_offer::text) > 4000 or octet_length(p_want::text) > 1000 then raise exception 'too big'; end if;
  if (select count(*) from trades where seller = p_id and status = 'open') >= 5 then raise exception 'too many trades'; end if;
  insert into trades (seller, seller_nick, to_player, offer, want) values (p_id, nick, p_to, p_offer, p_want) returning id into tid;
  return tid;
end $$;

create or replace function public.trade_list(p_id uuid) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', t.id, 'seller', t.seller, 'seller_nick', t.seller_nick, 'to_player', t.to_player,
    'offer', t.offer, 'want', t.want, 'status', t.status, 'buyer_nick', t.buyer_nick, 'mine', t.seller = p_id,
    'age', extract(epoch from now() - t.created_at)::int)
  from trades t
  where (t.status = 'open' and (t.to_player is null or t.to_player = p_id or t.seller = p_id))
     or (t.seller = p_id and t.status = 'taken')
  order by t.created_at desc
  limit 120;
$$;

create or replace function public.trade_take(p_id uuid, p_secret text, p_trade uuid, p_paid jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare nick text; res jsonb;
begin
  nick := trade_check(p_id, p_secret);
  if octet_length(coalesce(p_paid, '{}'::jsonb)::text) > 4000 then raise exception 'too big'; end if;
  update trades set status = 'taken', buyer = p_id, buyer_nick = nick, paid = p_paid, taken_at = now()
  where id = p_trade and status = 'open' and seller <> p_id and (to_player is null or to_player = p_id)
  returning offer into res;
  if res is null then raise exception 'trade gone'; end if;
  return res;
end $$;

create or replace function public.trade_cancel(p_id uuid, p_secret text, p_trade uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  perform trade_check(p_id, p_secret);
  update trades set status = 'cancelled' where id = p_trade and seller = p_id and status = 'open' returning offer into res;
  if res is null then raise exception 'trade gone'; end if;
  return res;
end $$;

create or replace function public.trade_close(p_id uuid, p_secret text, p_trade uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  perform trade_check(p_id, p_secret);
  update trades set status = 'closed' where id = p_trade and seller = p_id and status = 'taken' returning paid into res;
  if res is null then raise exception 'trade gone'; end if;
  return res;
end $$;

grant execute on function public.trade_create(uuid, text, jsonb, jsonb, uuid) to anon, authenticated;
grant execute on function public.trade_list(uuid) to anon, authenticated;
grant execute on function public.trade_take(uuid, text, uuid, jsonb) to anon, authenticated;
grant execute on function public.trade_cancel(uuid, text, uuid) to anon, authenticated;
grant execute on function public.trade_close(uuid, text, uuid) to anon, authenticated;
