-- Channels belong to a brand, not to an account.
--
-- connections was keyed by user_id back when a seller was a single storefront.
-- With brands that is wrong twice over: connecting eBay once would connect it
-- for every brand the account owns, and `unique (user_id, channel)` would then
-- stop a second brand from ever connecting eBay at all. @nike's eBay account is
-- not some other brand's.
--
-- connections, channel_credentials and listing_channels are all empty, so this
-- re-keys rather than migrates. channel_credentials hangs off connection_id and
-- is untouched - narrowing the parent narrows the credential with it, which is
-- the point of having split the secret out in the first place.

drop policy if exists "connections are self-readable" on public.connections;
drop policy if exists "connections are self-deletable" on public.connections;

alter table public.connections drop constraint if exists connections_user_id_channel_key;

alter table public.connections
  add column if not exists brand_id uuid references public.brands (id) on delete cascade;

-- Safe without a backfill only because the table is empty; check before reusing
-- this shape anywhere that has rows.
alter table public.connections alter column brand_id set not null;
alter table public.connections drop column if exists user_id;

alter table public.connections drop constraint if exists connections_brand_id_channel_key;
alter table public.connections add constraint connections_brand_id_channel_key
  unique (brand_id, channel);

-- Ownership is now one hop away, so the policies ask the brand. Same shape as
-- listing_channels, which has always had to reach through to listings.
drop policy if exists "connections are readable by the brand owner" on public.connections;
create policy "connections are readable by the brand owner"
  on public.connections for select using (
    exists (
      select 1 from public.brands b
      where b.id = connections.brand_id and b.owner_id = auth.uid()
    )
  );

drop policy if exists "connections are deletable by the brand owner" on public.connections;
create policy "connections are deletable by the brand owner"
  on public.connections for delete using (
    exists (
      select 1 from public.brands b
      where b.id = connections.brand_id and b.owner_id = auth.uid()
    )
  );

-- Still no insert or update policy: rows appear when the backend finishes an
-- OAuth round trip, never because the device asked.

create index if not exists connections_brand_idx on public.connections (brand_id);
