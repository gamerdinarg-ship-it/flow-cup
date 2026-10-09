-- FLOW CUP: friend groups and invite links
-- Run once in Supabase Dashboard -> SQL Editor -> New query.
-- Requires the existing public.profiles table with id, nickname, mmr, preferred_role columns.

create table if not exists public.cup_friend_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 2 and 40),
  owner_id uuid not null references auth.users(id) on delete cascade,
  invite_code text not null unique default encode(gen_random_bytes(12), 'hex'),
  max_members integer not null default 5 check (max_members between 2 and 5),
  created_at timestamptz not null default now()
);

create table if not exists public.cup_friend_group_members (
  group_id uuid not null references public.cup_friend_groups(id) on delete cascade,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  nickname text not null,
  mmr integer not null check (mmr between 0 and 15000),
  preferred_role text not null default 'any',
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

alter table public.cup_friend_groups enable row level security;
alter table public.cup_friend_group_members enable row level security;

-- All reads/writes go through controlled RPC functions; clients cannot directly edit group membership.
revoke all on public.cup_friend_groups from anon, authenticated;
revoke all on public.cup_friend_group_members from anon, authenticated;
grant usage on schema public to authenticated;

create or replace function public.cup_create_friend_group(p_name text)
returns table(group_id uuid, invite_code text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_profile record;
  v_group_id uuid;
  v_invite text;
begin
  if v_user is null then raise exception 'Нужно войти в аккаунт.'; end if;
  if char_length(trim(coalesce(p_name, ''))) < 2 or char_length(trim(p_name)) > 40 then
    raise exception 'Название группы должно быть от 2 до 40 символов.';
  end if;
  if exists (select 1 from public.cup_friend_group_members m where m.user_id = v_user) then
    raise exception 'Ты уже состоишь в группе. Сначала выйди из текущей группы.';
  end if;
  select p.nickname, p.mmr, p.preferred_role into v_profile
    from public.profiles p where p.id = v_user;
  if not found then raise exception 'Сначала заполни профиль FLOW CUP.'; end if;
  insert into public.cup_friend_groups(name, owner_id)
    values (trim(p_name), v_user) returning id, cup_friend_groups.invite_code into v_group_id, v_invite;
  insert into public.cup_friend_group_members(group_id, user_id, nickname, mmr, preferred_role)
    values (v_group_id, v_user, v_profile.nickname, v_profile.mmr, coalesce(v_profile.preferred_role, 'any'));
  return query select v_group_id, v_invite;
end;
$$;

create or replace function public.cup_join_friend_group(p_invite_code text)
returns table(group_id uuid, group_name text, member_count integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_group public.cup_friend_groups%rowtype;
  v_profile record;
  v_count integer;
begin
  if v_user is null then raise exception 'Чтобы вступить в группу, войди в аккаунт.'; end if;
  select g.* into v_group from public.cup_friend_groups g
    where g.invite_code = trim(coalesce(p_invite_code, ''));
  if not found then raise exception 'Ссылка-приглашение недействительна.'; end if;
  if exists (select 1 from public.cup_friend_group_members m where m.user_id = v_user and m.group_id = v_group.id) then
    select count(*)::integer into v_count from public.cup_friend_group_members m where m.group_id = v_group.id;
    return query select v_group.id, v_group.name, v_count;
    return;
  end if;
  if exists (select 1 from public.cup_friend_group_members m where m.user_id = v_user) then
    raise exception 'Ты уже состоишь в другой группе. Сначала выйди из неё.';
  end if;
  select p.nickname, p.mmr, p.preferred_role into v_profile
    from public.profiles p where p.id = v_user;
  if not found then raise exception 'Сначала заполни профиль FLOW CUP.'; end if;
  select count(*)::integer into v_count from public.cup_friend_group_members m where m.group_id = v_group.id;
  if v_count >= v_group.max_members then raise exception 'Группа уже заполнена.'; end if;
  insert into public.cup_friend_group_members(group_id, user_id, nickname, mmr, preferred_role)
    values (v_group.id, v_user, v_profile.nickname, v_profile.mmr, coalesce(v_profile.preferred_role, 'any'));
  select count(*)::integer into v_count from public.cup_friend_group_members m where m.group_id = v_group.id;
  return query select v_group.id, v_group.name, v_count;
end;
$$;

create or replace function public.cup_get_my_friend_group()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_group_id uuid;
  v_result jsonb;
begin
  if v_user is null then return null; end if;
  select m.group_id into v_group_id
    from public.cup_friend_group_members m where m.user_id = v_user;
  if v_group_id is null then return null; end if;
  select jsonb_build_object(
    'id', g.id,
    'name', g.name,
    'invite_code', g.invite_code,
    'owner_id', g.owner_id,
    'max_members', g.max_members,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', m.user_id,
        'nickname', m.nickname,
        'mmr', m.mmr,
        'preferred_role', m.preferred_role,
        'joined_at', m.joined_at
      ) order by m.joined_at)
      from public.cup_friend_group_members m where m.group_id = g.id
    ), '[]'::jsonb)
  ) into v_result
  from public.cup_friend_groups g where g.id = v_group_id;
  return v_result;
end;
$$;

create or replace function public.cup_leave_friend_group()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_group_id uuid;
  v_owner uuid;
  v_next_owner uuid;
begin
  if v_user is null then raise exception 'Нужно войти в аккаунт.'; end if;
  select m.group_id into v_group_id from public.cup_friend_group_members m where m.user_id = v_user;
  if v_group_id is null then return false; end if;
  select g.owner_id into v_owner from public.cup_friend_groups g where g.id = v_group_id;
  delete from public.cup_friend_group_members m where m.group_id = v_group_id and m.user_id = v_user;
  if v_owner = v_user then
    select m.user_id into v_next_owner from public.cup_friend_group_members m
      where m.group_id = v_group_id order by m.joined_at limit 1;
    if v_next_owner is null then
      delete from public.cup_friend_groups g where g.id = v_group_id;
    else
      update public.cup_friend_groups g set owner_id = v_next_owner where g.id = v_group_id;
    end if;
  end if;
  return true;
end;
$$;

revoke all on function public.cup_create_friend_group(text) from public, anon;
revoke all on function public.cup_join_friend_group(text) from public, anon;
revoke all on function public.cup_get_my_friend_group() from public, anon;
revoke all on function public.cup_leave_friend_group() from public, anon;
grant execute on function public.cup_create_friend_group(text) to authenticated;
grant execute on function public.cup_join_friend_group(text) to authenticated;
grant execute on function public.cup_get_my_friend_group() to authenticated;
grant execute on function public.cup_leave_friend_group() to authenticated;
