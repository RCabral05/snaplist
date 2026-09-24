-- The Shop feed.
--
-- Until now every listing row was a draft as far as Postgres was concerned:
-- publishing wrote a ChannelListing into AsyncStorage on one device and nothing
-- else. published_at is the first thing in the database that says an item is
-- actually for sale, and it is what the feed and the new read policies key on.
--
-- Publishing to `snaplist` is the one channel the device may mark itself. It is
-- our own marketplace, so there is no OAuth token and no backend in the way -
-- unlike ebay and shopify, whose states still come from the service role.

alter table public.listings add column if not exists published_at timestamptz;

create index if not exists listings_published_idx
  on public.listings (published_at desc)
  where published_at is not null;

-- Sits alongside "listings are self-managed", which stays. Policies are
-- permissive and OR together: you can still see all of your own rows, and now
-- everyone can see the published ones.
drop policy if exists "published listings are readable" on public.listings;
create policy "published listings are readable"
  on public.listings for select to authenticated
  using (published_at is not null);

-- Objects live at <uid>/<listingId>/<file>, so the listing id is segment 2 and
-- the photo's visibility can be derived from its listing instead of copying the
-- file into a second, public bucket when it goes live. The bucket stays private:
-- the whole app is behind sign-in, so a signed URL is all a buyer ever needs.
drop policy if exists "photos of published listings are readable" on storage.objects;
create policy "photos of published listings are readable"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'listing-photos'
    and exists (
      select 1 from public.listings l
      where l.id::text = (storage.foldername(name))[2]
        and l.published_at is not null
    )
  );

-- Sellers on the feed.
--
-- A read policy on profiles would expose every column of the row, because RLS is
-- row-level - the same reason channel_credentials is its own table. A view is the
-- column-level answer: profiles itself stays owner-only, and exactly these four
-- columns are reachable by anyone. Note this is deliberately NOT security_invoker;
-- running as the definer is what lets it see past the table's own policy.
create or replace view public.public_profiles as
  select id, username, display_name, avatar_url
  from public.profiles;

grant select on public.public_profiles to authenticated, anon;
