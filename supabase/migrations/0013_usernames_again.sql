-- Usernames, back.
--
-- 0011 dropped the column and the two RPCs along with the marketplace, because
-- the handle had moved to brands.slug and brands were going. The handle is
-- wanted on the profile after all, so this restores what 0002 built - the same
-- functions, the same reasoning - minus anything to do with storefronts.
--
-- Nullable on purpose. There is no onboarding gate any more: someone signs in,
-- lands on home, and picks a name when they feel like it or never.

alter table public.profiles add column if not exists username text;

-- Case-preserving for display, case-insensitive for uniqueness: Ryan and ryan
-- must not be two different people.
create unique index if not exists profiles_username_lower_idx
  on public.profiles (lower(username));

alter table public.profiles drop constraint if exists profiles_username_format;
alter table public.profiles add constraint profiles_username_format
  check (username is null or username ~ '^[A-Za-z0-9_]{3,20}$');

-- Names to keep back for routes, support, or impersonation reasons.
create or replace function public.username_reserved(candidate text)
returns boolean language sql immutable as $$
  select lower(candidate) = any (array[
    'admin', 'administrator', 'snaplist', 'support', 'help', 'about', 'api',
    'root', 'system', 'moderator', 'mod', 'staff', 'team', 'official',
    'settings', 'account', 'profile', 'login', 'signin', 'signup', 'register',
    'me', 'new', 'null', 'undefined'
  ]);
$$;

/**
 * Is this username free? Returns false for badly formed and reserved names too,
 * so the caller needs one round trip rather than three.
 *
 * It has to be security definer: profiles is readable only by its owner, so a
 * client-side "select 1 where username = ?" comes back empty for every name and
 * reports the whole namespace as available.
 */
create or replace function public.username_available(candidate text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  normalized text := lower(trim(candidate));
begin
  if normalized is null or normalized !~ '^[a-z0-9_]{3,20}$' then
    return false;
  end if;
  if public.username_reserved(normalized) then
    return false;
  end if;
  return not exists (
    select 1 from public.profiles where lower(username) = normalized
  );
end;
$$;

/**
 * Claim it. Checking and then setting from the app would race: two people can
 * both be told a name is free before either writes. The unique index is the real
 * arbiter and this reports its verdict as a clean error.
 */
create or replace function public.claim_username(candidate text)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  cleaned text := trim(candidate);
begin
  if uid is null then
    raise exception 'not_authenticated';
  end if;
  if cleaned !~ '^[A-Za-z0-9_]{3,20}$' then
    raise exception 'invalid_username';
  end if;
  if public.username_reserved(cleaned) then
    raise exception 'username_taken';
  end if;

  insert into public.profiles (id, username)
  values (uid, cleaned)
  on conflict (id) do update set username = excluded.username;

  return cleaned;
exception
  when unique_violation then
    raise exception 'username_taken';
end;
$$;

revoke all on function public.username_available(text) from public;
revoke all on function public.claim_username(text) from public;
grant execute on function public.username_available(text) to authenticated;
grant execute on function public.claim_username(text) to authenticated;
