-- Profile images.
--
-- The file lives in Storage, not in the table: Postgres is a poor place for
-- binaries and the app needs a URL it can hand straight to <Image>. The bucket
-- is public-read because a storefront is meant to be seen by buyers who are not
-- signed in - a signed URL per avatar would cost a round trip to render a list.
-- Write access is the part that matters, and it is narrowed below to the one
-- folder named after the owner's uid.

alter table public.profiles add column if not exists avatar_url text;

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

-- Anyone may look. There is nothing private in a profile picture, and buyers
-- browsing a storefront are not authenticated.
drop policy if exists "avatars are world-readable" on storage.objects;
create policy "avatars are world-readable"
  on storage.objects for select
  using (bucket_id = 'avatars');

-- Writes are confined to <uid>/... so one seller cannot overwrite another's
-- picture. storage.foldername() splits the object name on "/"; element 1 is the
-- first path segment.
drop policy if exists "sellers write their own avatar" on storage.objects;
create policy "sellers write their own avatar"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "sellers replace their own avatar" on storage.objects;
create policy "sellers replace their own avatar"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "sellers delete their own avatar" on storage.objects;
create policy "sellers delete their own avatar"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
