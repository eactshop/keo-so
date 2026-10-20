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
