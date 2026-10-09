-- FLOW CUP organizer panel + persistent tournaments + application statuses
-- 1) Run this whole file in Supabase Dashboard -> SQL Editor -> New query.
-- 2) To make your account an organizer, run the separate INSERT shown at the bottom
--    after replacing the UUID with your account ID from Authentication -> Users.

create table if not exists public.cup_tournament_organizers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.cup_tournament_organizers enable row level security;
drop policy if exists "Organizers can see their own role" on public.cup_tournament_organizers;
create policy "Organizers can see their own role" on public.cup_tournament_organizers
  for select to authenticated using (auth.uid() = user_id);
grant select on public.cup_tournament_organizers to authenticated;

create table if not exists public.cup_tournaments (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (char_length(trim(name)) between 1 and 50),
  format text not null default '5×5' check (format in ('5×5','Mix','Stack')),
  team_limit integer not null default 8 check (team_limit in (4,8,16)),
  description text not null default '',
  status text not null default 'open' check (status in ('open','closed')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
alter table public.cup_tournaments enable row level security;
drop policy if exists "Anyone can read tournaments" on public.cup_tournaments;
create policy "Anyone can read tournaments" on public.cup_tournaments
  for select using (true);
drop policy if exists "Organizers can create tournaments" on public.cup_tournaments;
create policy "Organizers can create tournaments" on public.cup_tournaments
  for insert to authenticated with check (auth.uid() = created_by and exists (
    select 1 from public.cup_tournament_organizers o where o.user_id = auth.uid()
  ));
drop policy if exists "Organizers can update tournaments" on public.cup_tournaments;
create policy "Organizers can update tournaments" on public.cup_tournaments
  for update to authenticated using (exists (
    select 1 from public.cup_tournament_organizers o where o.user_id = auth.uid()
  )) with check (exists (
    select 1 from public.cup_tournament_organizers o where o.user_id = auth.uid()
  ));
drop policy if exists "Organizers can delete tournaments" on public.cup_tournaments;
create policy "Organizers can delete tournaments" on public.cup_tournaments
  for delete to authenticated using (exists (
    select 1 from public.cup_tournament_organizers o where o.user_id = auth.uid()
  ));
grant select on public.cup_tournaments to anon, authenticated;
grant insert, update, delete on public.cup_tournaments to authenticated;

alter table public.cup_tournament_entries
  add column if not exists status text not null default 'pending'
  check (status in ('pending','approved','rejected'));
drop policy if exists "Organizers can update tournament entry status" on public.cup_tournament_entries;
create policy "Organizers can update tournament entry status" on public.cup_tournament_entries
  for update to authenticated using (exists (
    select 1 from public.cup_tournament_organizers o where o.user_id = auth.uid()
  )) with check (exists (
    select 1 from public.cup_tournament_organizers o where o.user_id = auth.uid()
  ));

-- To assign your account as organizer, find your UUID under Supabase -> Authentication -> Users,
-- then run this separately, replacing YOUR-USER-UUID:
-- insert into public.cup_tournament_organizers (user_id) values ('YOUR-USER-UUID')
-- on conflict (user_id) do nothing;
