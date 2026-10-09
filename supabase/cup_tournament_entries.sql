-- FLOW CUP: shared tournament applications
-- Run this entire file in Supabase Dashboard -> SQL Editor -> New query.

create table if not exists public.cup_tournament_entries (
  id uuid primary key default gen_random_uuid(),
  tournament_name text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  nickname text not null,
  mmr integer not null check (mmr between 0 and 15000),
  preferred_role text not null default 'any',
  entry_type text not null check (entry_type in ('solo','duo','party3','party4','stack5')),
  party_name text,
  party_members text[] not null default '{}',
  party_size integer not null check (party_size between 1 and 5),
  created_at timestamptz not null default now(),
  constraint cup_tournament_entries_one_entry_per_user unique (tournament_name, user_id)
);

alter table public.cup_tournament_entries enable row level security;

drop policy if exists "Anyone can read tournament entry summaries" on public.cup_tournament_entries;
create policy "Anyone can read tournament entry summaries"
  on public.cup_tournament_entries for select
  using (true);

drop policy if exists "Users can submit their own tournament entries" on public.cup_tournament_entries;
create policy "Users can submit their own tournament entries"
  on public.cup_tournament_entries for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their own tournament entries" on public.cup_tournament_entries;
create policy "Users can update their own tournament entries"
  on public.cup_tournament_entries for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own tournament entries" on public.cup_tournament_entries;
create policy "Users can delete their own tournament entries"
  on public.cup_tournament_entries for delete
  to authenticated
  using (auth.uid() = user_id);

grant select on public.cup_tournament_entries to anon, authenticated;
grant insert, update, delete on public.cup_tournament_entries to authenticated;
