-- Listing photos.
--
-- Unlike avatars, this bucket is private. A draft is not public - it is a
-- photograph of something in the seller's house, taken before they have decided
-- whether to sell it - so the object is readable only by its owner and the app
-- signs a URL when it needs to draw one. When the Shop feed exists and a listing
-- is actually published, the published copy is what becomes world-readable;
-- that is a later migration, not this one.
--
-- Same prefix convention as avatars: <uid>/... is the only place a seller may
-- write, which is what makes the policies one line each.

insert into storage.buckets (id, name, public)
values ('listing-photos', 'listing-photos', false)
on conflict (id) do update set public = false;

drop policy if exists "sellers read their own listing photos" on storage.objects;
create policy "sellers read their own listing photos"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "sellers write their own listing photos" on storage.objects;
create policy "sellers write their own listing photos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "sellers replace their own listing photos" on storage.objects;
create policy "sellers replace their own listing photos"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "sellers delete their own listing photos" on storage.objects;
create policy "sellers delete their own listing photos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
