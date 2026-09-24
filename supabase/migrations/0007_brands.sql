-- Brands.
--
-- A seller is a person; a brand is what they sell under. Until now those were
-- the same thing - profiles.username was the storefront handle - which stops
-- working the moment anything other than a product hangs off a seller. Events
-- are the next such thing, and they will point at a brand, not at a user.
--
-- So the handle moves. @nike is a brand, not a person, and profiles keeps
-- display_name and avatar_url as the private human behind it. profiles.username
-- is left in place rather than dropped: it is the source for the backfill below,
-- and dropping a column is not something to do in the same migration that stops
-- reading it. Nothing in the app uses it after this.

create table if not exists public.brands (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  slug text not null,
  name text not null default '',
  logo_url text,
  bio text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint brands_slug_format check (slug ~ '^[A-Za-z0-9_]{3,20}$')
);

-- Same rule usernames had: case-preserving for display, case-insensitive for
-- uniqueness, so Nike and nike cannot be two different brands.
create unique index if not exists brands_slug_lower_idx on public.brands (lower(slug));
create index if not exists brands_owner_idx on public.brands (owner_id, created_at);

alter table public.brands enable row level security;

drop policy if exists "brands are managed by their owner" on public.brands;
create policy "brands are managed by their owner"
  on public.brands for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- The storefront is public, but the table is not: a policy would expose
-- owner_id, which maps a brand to a person. The view is the column-level answer,
-- exactly as public_profiles is for profiles.
create or replace view public.public_brands as
  select id, slug, name, logo_url, bio, created_at
  from public.brands;

grant select on public.public_brands to authenticated, anon;

-- ------------------------------------------------------------ slug claiming ---
-- Lifted from the username functions, which keep working but are no longer
-- called by the app. username_reserved is reused as-is: the names we want to
-- keep for routes are the same set either way.

create or replace function public.brand_slug_available(candidate text)
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
  return not exists (select 1 from public.brands where lower(slug) = normalized);
end;
$$;

/**
 * Create a brand and take its slug in one statement. Checking then inserting
 * from the app would race; the unique index is the real arbiter and this reports
 * its verdict as a clean error, the way claim_username always did.
 */
create or replace function public.create_brand(candidate text, brand_name text default '')
returns public.brands
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  cleaned text := trim(candidate);
  created public.brands;
begin
  if uid is null then
    raise exception 'not_authenticated';
  end if;
  if cleaned !~ '^[A-Za-z0-9_]{3,20}$' then
    raise exception 'invalid_slug';
  end if;
  if public.username_reserved(cleaned) then
    raise exception 'slug_taken';
  end if;

  insert into public.brands (owner_id, slug, name)
  values (uid, cleaned, coalesce(nullif(trim(brand_name), ''), cleaned))
  returning * into created;

  return created;
exception
  when unique_violation then
    raise exception 'slug_taken';
end;
$$;

/** Rename. Same arbitration, and the owner check is the RLS policy's job. */
create or replace function public.rename_brand(target uuid, candidate text)
returns public.brands
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  cleaned text := trim(candidate);
  updated public.brands;
begin
  if uid is null then
    raise exception 'not_authenticated';
  end if;
  if cleaned !~ '^[A-Za-z0-9_]{3,20}$' then
    raise exception 'invalid_slug';
  end if;
  if public.username_reserved(cleaned) then
    raise exception 'slug_taken';
  end if;

  update public.brands
     set slug = cleaned, updated_at = now()
   where id = target and owner_id = uid
  returning * into updated;

  if updated is null then
    raise exception 'not_found';
  end if;
  return updated;
exception
  when unique_violation then
    raise exception 'slug_taken';
end;
$$;

revoke all on function public.brand_slug_available(text) from public;
revoke all on function public.create_brand(text, text) from public;
revoke all on function public.rename_brand(uuid, text) from public;
grant execute on function public.brand_slug_available(text) to authenticated;
grant execute on function public.create_brand(text, text) to authenticated;
grant execute on function public.rename_brand(uuid, text) to authenticated;

-- ------------------------------------------------------------------ logos ---
insert into storage.buckets (id, name, public)
values ('brand-logos', 'brand-logos', true)
on conflict (id) do update set public = true;

drop policy if exists "brand logos are world-readable" on storage.objects;
create policy "brand logos are world-readable"
  on storage.objects for select
  using (bucket_id = 'brand-logos');

drop policy if exists "owners write their own brand logos" on storage.objects;
create policy "owners write their own brand logos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'brand-logos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "owners replace their own brand logos" on storage.objects;
create policy "owners replace their own brand logos"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'brand-logos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'brand-logos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "owners delete their own brand logos" on storage.objects;
create policy "owners delete their own brand logos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'brand-logos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- --------------------------------------------------------------- listings ---
alter table public.listings add column if not exists brand_id uuid references public.brands (id) on delete cascade;

-- Backfill: every seller who had claimed a username gets that username as their
-- first brand, and their listings move under it. Without this, an account that
-- already exists would be sent back through onboarding and its listings would
-- belong to no brand.
insert into public.brands (owner_id, slug, name, logo_url)
select p.id, p.username, coalesce(nullif(p.display_name, ''), p.username), p.avatar_url
from public.profiles p
where p.username is not null
  and not exists (select 1 from public.brands b where b.owner_id = p.id)
on conflict do nothing;

update public.listings l
   set brand_id = b.id
  from public.brands b
 where l.brand_id is null
   and b.owner_id = l.user_id;

create index if not exists listings_brand_idx on public.listings (brand_id, updated_at desc);
