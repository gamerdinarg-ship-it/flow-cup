-- FLOW CUP: private, persistent team-balance drafts
-- Run once in Supabase Dashboard -> SQL Editor -> New query.
-- Drafts are private to the signed-in user. This does NOT publish team compositions.

create table if not exists public.cup_team_balance_drafts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  tournament_name text not null check (char_length(trim(tournament_name)) between 1 and 100),
  team_count integer not null check (team_count in (2, 4, 8, 16)),
  composition jsonb not null,
  updated_at timestamptz not null default now(),
  constraint cup_team_balance_drafts_user_tournament_unique unique (user_id, tournament_name)
);

alter table public.cup_team_balance_drafts enable row level security;

drop policy if exists "Users can read their own balance drafts" on public.cup_team_balance_drafts;
create policy "Users can read their own balance drafts"
  on public.cup_team_balance_drafts for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can insert their own balance drafts" on public.cup_team_balance_drafts;
create policy "Users can insert their own balance drafts"
  on public.cup_team_balance_drafts for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their own balance drafts" on public.cup_team_balance_drafts;
create policy "Users can update their own balance drafts"
  on public.cup_team_balance_drafts for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own balance drafts" on public.cup_team_balance_drafts;
create policy "Users can delete their own balance drafts" on public.cup_team_balance_drafts
  for delete to authenticated using (auth.uid() = user_id);

grant select, insert, update, delete on public.cup_team_balance_drafts to authenticated;
