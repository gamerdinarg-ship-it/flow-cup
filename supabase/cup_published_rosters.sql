-- FLOW CUP: public team rosters published by organizers
-- Run in Supabase Dashboard -> SQL Editor -> New query.

create table if not exists public.cup_published_rosters (
  id uuid primary key default gen_random_uuid(),
  tournament_name text not null unique check (char_length(trim(tournament_name)) between 1 and 100),
  team_count integer not null check (team_count in (2, 4, 8, 16)),
  composition jsonb not null,
  published_by uuid not null references auth.users(id),
  published_at timestamptz not null default now()
);

alter table public.cup_published_rosters enable row level security;

drop policy if exists "Anyone can read published rosters" on public.cup_published_rosters;
create policy "Anyone can read published rosters"
  on public.cup_published_rosters for select
  to anon, authenticated using (true);

drop policy if exists "Organizers can publish rosters" on public.cup_published_rosters;
create policy "Organizers can publish rosters"
  on public.cup_published_rosters for insert
  to authenticated
  with check (
    auth.uid() = published_by
    and exists (select 1 from public.cup_tournament_organizers o where o.user_id = auth.uid())
  );

drop policy if exists "Organizers can update published rosters" on public.cup_published_rosters;
create policy "Organizers can update published rosters"
  on public.cup_published_rosters for update
  to authenticated
  using (exists (select 1 from public.cup_tournament_organizers o where o.user_id = auth.uid()))
  with check (
    auth.uid() = published_by
    and exists (select 1 from public.cup_tournament_organizers o where o.user_id = auth.uid())
  );

drop policy if exists "Organizers can delete published rosters" on public.cup_published_rosters;
create policy "Organizers can delete published rosters"
  on public.cup_published_rosters for delete
  to authenticated
  using (exists (select 1 from public.cup_tournament_organizers o where o.user_id = auth.uid()));

grant select on public.cup_published_rosters to anon, authenticated;
grant insert, update, delete on public.cup_published_rosters to authenticated;
