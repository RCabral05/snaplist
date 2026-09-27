-- Remove the marketplace.
--
-- The app was stripped back to auth and a profile on 2026-09-27; this takes the
-- schema with it. Irreversible, unlike the code, so a JSON snapshot of every
-- table below was taken first (snaplist-marketplace-snapshot-2026-09-27.json,
-- kept outside the repo - it contains seller rows).
--
-- What survives: profiles, the handle_new_user trigger that fills it, and the
-- avatars bucket. Everything else here existed to sell things.

begin;

-- ------------------------------------------------------------ seed sellers ---
-- Five fake accounts from demo_marketplace.sql. Deleting the users cascades to
-- their profiles, brands and listings, so this goes first and does most of the
-- work before the tables are dropped underneath it.
delete from auth.users where email like '%@seed.snaplist.test';

-- ------------------------------------------------------------------ tables ---
-- Child first. channel_credentials points at connections, listing_channels at
-- listings, and listings at brands.
drop table if exists public.channel_credentials cascade;
drop table if exists public.connections cascade;
drop table if exists public.listing_channels cascade;
drop table if exists public.listings cascade;
drop table if exists public.brands cascade;

-- ------------------------------------------------------------------- views ---
-- public_brands showed storefronts. public_profiles existed so a buyer could see
-- who was selling; with no buyers it is a public read of every profile row for
-- nobody, which is worth removing on its own merits.
drop view if exists public.public_brands;
drop view if exists public.public_profiles;

-- --------------------------------------------------------------- functions ---
-- The two-RPC handle-claiming pattern, in both its brand and username forms.
drop function if exists public.brand_slug_available(text);
drop function if exists public.create_brand(text, text);
drop function if exists public.rename_brand(uuid, text);
drop function if exists public.username_available(text);
drop function if exists public.claim_username(text);
drop function if exists public.username_reserved(text);

-- ----------------------------------------------------------------- storage ---
-- Policies live on storage.objects and are filtered by bucket_id, so dropping a
-- bucket does not remove them. The avatars policies are deliberately untouched.
drop policy if exists "sellers read their own listing photos" on storage.objects;
drop policy if exists "sellers write their own listing photos" on storage.objects;
drop policy if exists "sellers replace their own listing photos" on storage.objects;
drop policy if exists "sellers delete their own listing photos" on storage.objects;
drop policy if exists "photos of published listings are readable" on storage.objects;
drop policy if exists "brand logos are world-readable" on storage.objects;
drop policy if exists "owners write their own brand logos" on storage.objects;
drop policy if exists "owners replace their own brand logos" on storage.objects;
drop policy if exists "owners delete their own brand logos" on storage.objects;

-- The buckets themselves are NOT dropped here. Supabase refuses direct deletes
-- from storage tables ("Use the Storage API instead"), which is right - a row
-- delete would orphan the files rather than remove them. With the policies gone
-- the two buckets are unreachable by anyone but the service role; emptying and
-- deleting them is a dashboard job, or an API call with a service-role key.
--
--   Storage -> listing-photos -> delete bucket   (6 objects)
--   Storage -> brand-logos    -> delete bucket   (empty)

-- ---------------------------------------------------------------- profiles ---
-- The storefront handle, from before brands. Nothing has read it since 0007.
alter table public.profiles drop column if exists username;

commit;
