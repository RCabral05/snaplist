-- Snaplist, initial schema.
--
-- The one rule that shapes everything here: marketplace tokens must never be
-- readable by the app. Postgres RLS is row-level, not column-level, so the
-- secrets live in their own table with NO policies at all - which means only the
-- service role (the backend) can touch them. Sellers see `connections`, which
-- carries the fact of a connection and nothing sensitive.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- profiles ---
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles are self-readable" on public.profiles;
create policy "profiles are self-readable"
  on public.profiles for select using (auth.uid() = id);

drop policy if exists "profiles are self-writable" on public.profiles;
create policy "profiles are self-writable"
  on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);

-- One profile per auth user, created the moment they sign up.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------- connections ---
-- Non-secret. The seller may read and delete their own rows.
create table if not exists public.connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  channel text not null check (channel in ('ebay', 'shopify')),
  label text,
  status text not null default 'active' check (status in ('active', 'expired', 'revoked')),
  connected_at timestamptz not null default now(),
  unique (user_id, channel)
);

alter table public.connections enable row level security;

drop policy if exists "connections are self-readable" on public.connections;
create policy "connections are self-readable"
  on public.connections for select using (auth.uid() = user_id);

drop policy if exists "connections are self-deletable" on public.connections;
create policy "connections are self-deletable"
  on public.connections for delete using (auth.uid() = user_id);

-- Deliberately no insert/update policy: rows are created by the backend at the
-- end of the OAuth round trip, never by the device.

-- ------------------------------------------------------- channel_credentials --
-- Secret. No RLS policies at all, so only the service role can read or write.
create table if not exists public.channel_credentials (
  connection_id uuid primary key references public.connections (id) on delete cascade,
  access_token text not null,
  refresh_token text,
  expires_at timestamptz,
  scope text,
  updated_at timestamptz not null default now()
);

alter table public.channel_credentials enable row level security;

-- ---------------------------------------------------------------- listings ---
create table if not exists public.listings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null default '',
  description text not null default '',
  price_cents integer not null default 0 check (price_cents >= 0),
  currency text not null default 'USD',
  condition text not null default 'good'
    check (condition in ('new', 'like_new', 'good', 'fair', 'parts')),
  quantity integer not null default 1 check (quantity >= 0),
  category text,
  brand text,
  photos text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.listings enable row level security;

drop policy if exists "listings are self-managed" on public.listings;
create policy "listings are self-managed"
  on public.listings for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create index if not exists listings_user_idx on public.listings (user_id, updated_at desc);

-- -------------------------------------------------------- listing_channels ---
-- One row per (listing, channel). Publishing is not all-or-nothing: eBay can
-- reject while Shopify accepts, so each channel carries its own state.
create table if not exists public.listing_channels (
  listing_id uuid not null references public.listings (id) on delete cascade,
  channel text not null check (channel in ('snaplist', 'ebay', 'shopify')),
  state text not null default 'draft'
    check (state in ('draft', 'pending', 'live', 'failed', 'ended')),
  remote_id text,
  remote_url text,
  message text,
  updated_at timestamptz not null default now(),
  primary key (listing_id, channel)
);

alter table public.listing_channels enable row level security;

drop policy if exists "listing channels follow the listing" on public.listing_channels;
create policy "listing channels follow the listing"
  on public.listing_channels for select using (
    exists (
      select 1 from public.listings l
      where l.id = listing_channels.listing_id and l.user_id = auth.uid()
    )
  );

-- Writes come from the backend after a publish attempt, so no insert/update
-- policy for the device here either.
