-- Usernames.
--
-- Availability cannot be checked from the client: profiles is readable only by
-- its owner, so "select 1 from profiles where username = ?" always comes back
-- empty and every name looks free. Both the check and the claim are therefore
-- security-definer functions - the only things allowed to see across rows, and
-- they expose exactly one bit each.

alter table public.profiles add column if not exists username text;

-- Case-preserving for display, case-insensitive for uniqueness: Ryan and ryan
-- must not be two different sellers.
create unique index if not exists profiles_username_lower_idx
  on public.profiles (lower(username));

alter table public.profiles drop constraint if exists profiles_username_format;
alter table public.profiles add constraint profiles_username_format
  check (username is null or username ~ '^[A-Za-z0-9_]{3,20}$');

-- Names we will want later for routes, support or impersonation reasons.
create or replace function public.username_reserved(candidate text)
returns boolean language sql immutable as $$
  select lower(candidate) = any (array[
    'admin', 'administrator', 'snaplist', 'support', 'help', 'about', 'api',
    'root', 'system', 'moderator', 'mod', 'staff', 'team', 'official',
    'settings', 'account', 'login', 'signin', 'signup', 'register', 'me',
    'shop', 'sell', 'listings', 'search', 'new', 'null', 'undefined'
  ]);
$$;

/**
 * Is this username free? Returns false for badly formed and reserved names too,
 * so the caller needs one round trip, not three.
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
 * Claim it. Checking then setting from the app would race: two people can both
 * be told a name is free before either writes. The unique index is the real
 * arbiter and this function reports its verdict as a clean error.
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

-- Let the owner read their own username back.
drop policy if exists "profiles are self-readable" on public.profiles;
create policy "profiles are self-readable"
  on public.profiles for select using (auth.uid() = id);
