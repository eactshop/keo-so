-- Bảng xếp hạng cho Kéo Số 10.
-- Chạy toàn bộ file này một lần trong Supabase → SQL Editor → New query → Run.

create table if not exists public.scores (
  id bigint generated always as identity primary key,
  name text not null check (char_length(btrim(name)) between 1 and 20),
  mode text not null check (mode in ('classic', 'zen')),
  score int not null check (score between 1 and 170), -- bàn 10x17 = tối đa 170 quả
  created_at timestamptz not null default now()
);
create index if not exists scores_mode_score_idx on public.scores (mode, score desc);

-- Chế độ Full màn: bàn 14x24 = tối đa 336 quả (cập nhật ràng buộc cho bảng đã tạo từ trước)
alter table public.scores drop constraint if exists scores_mode_check;
alter table public.scores add constraint scores_mode_check check (mode in ('classic', 'zen', 'full'));
alter table public.scores drop constraint if exists scores_score_check;
alter table public.scores add constraint scores_score_check check (score between 1 and 336);

-- Ai cũng được xem và gửi điểm; không ai được sửa/xoá qua API
alter table public.scores enable row level security;
drop policy if exists "public read" on public.scores;
create policy "public read" on public.scores for select to anon, authenticated using (true);
drop policy if exists "public insert" on public.scores;
create policy "public insert" on public.scores for insert to anon, authenticated with check (true);
grant select, insert on public.scores to anon, authenticated;

-- Mỗi tên (không phân biệt hoa/thường) chỉ giữ điểm cao nhất của từng chế độ
create or replace view public.leaderboard with (security_invoker = true) as
select distinct on (mode, lower(btrim(name)))
  btrim(name) as name, mode, score, created_at
from public.scores
order by mode, lower(btrim(name)), score desc, created_at asc;
grant select on public.leaderboard to anon, authenticated;

-- BXH theo khoảng thời gian (p_since = null → mọi lúc), gộp theo tên:
-- best = điểm cao nhất, total = tổng điểm đã chơi, plays = số ván.
-- p_sort = 'best' hoặc 'total'.
create index if not exists scores_mode_created_idx on public.scores (mode, created_at);
create or replace function public.leaderboard_period(
  p_mode text, p_since timestamptz default null, p_sort text default 'best', p_limit int default 50
) returns table (name text, best int, total bigint, plays bigint)
language sql stable security invoker as $$
  select (array_agg(btrim(s.name) order by s.score desc, s.created_at))[1],
         max(s.score), sum(s.score), count(*)
  from public.scores s
  where s.mode = p_mode and (p_since is null or s.created_at >= p_since)
  group by lower(btrim(s.name))
  order by case when p_sort = 'total' then sum(s.score) else max(s.score) end desc,
           case when p_sort = 'total' then max(s.score) else sum(s.score) end desc,
           min(s.created_at)
  limit least(greatest(p_limit, 1), 200);
$$;
grant execute on function public.leaderboard_period(text, timestamptz, text, int) to anon, authenticated;

-- ---------- Solo 1v1 ----------
-- Mỗi trận một dòng; p1 = người mời, p2 = người nhận. winner: 1 / 2, null = hoà.
-- Thắng +1 điểm, thua −1 điểm, hoà 0.
create table if not exists public.solo_matches (
  id text primary key check (char_length(id) between 8 and 40),
  p1 text not null check (char_length(btrim(p1)) between 1 and 20),
  p2 text not null check (char_length(btrim(p2)) between 1 and 20),
  s1 int not null check (s1 between 0 and 170),
  s2 int not null check (s2 between 0 and 170),
  winner smallint check (winner in (1, 2)),
  forfeit boolean not null default false, -- true = một bên bỏ trận
  created_at timestamptz not null default now(),
  check (lower(btrim(p1)) <> lower(btrim(p2)))
);
create index if not exists solo_matches_created_idx on public.solo_matches (created_at);

alter table public.solo_matches enable row level security;
drop policy if exists "public read" on public.solo_matches;
create policy "public read" on public.solo_matches for select to anon, authenticated using (true);
drop policy if exists "public insert" on public.solo_matches;
create policy "public insert" on public.solo_matches for insert to anon, authenticated with check (true);
grant select, insert on public.solo_matches to anon, authenticated;

-- BXH solo theo khoảng thời gian (p_since = null → mọi lúc), gộp theo tên
create or replace function public.solo_leaderboard(p_since timestamptz default null, p_limit int default 50)
returns table (name text, points bigint, wins bigint, losses bigint, draws bigint)
language sql stable security invoker as $$
  with t as (
    select btrim(p1) as name, created_at, case winner when 1 then 1 when 2 then -1 else 0 end as d
    from public.solo_matches where p_since is null or created_at >= p_since
    union all
    select btrim(p2), created_at, case winner when 2 then 1 when 1 then -1 else 0 end
    from public.solo_matches where p_since is null or created_at >= p_since
  )
  select (array_agg(t.name order by t.created_at desc))[1], sum(t.d),
         count(*) filter (where t.d = 1), count(*) filter (where t.d = -1), count(*) filter (where t.d = 0)
  from t
  group by lower(t.name)
  order by sum(t.d) desc, count(*) filter (where t.d = 1) desc, count(*) asc
  limit least(greatest(p_limit, 1), 200);
$$;
grant execute on function public.solo_leaderboard(timestamptz, int) to anon, authenticated;
