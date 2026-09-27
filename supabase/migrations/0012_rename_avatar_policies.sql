-- The last of the marketplace vocabulary.
--
-- These policies survived 0011 because avatars did, but they were named when
-- everyone was a seller. There are no sellers; there are people with profiles.
--
-- Dropped and recreated rather than renamed: ALTER POLICY ... RENAME needs
-- ownership of storage.objects, which belongs to supabase_storage_admin, while
-- create and drop are permitted. The rules are byte-for-byte what they were.

drop policy if exists "sellers write their own avatar" on storage.objects;
create policy "owners write their own avatar"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "sellers replace their own avatar" on storage.objects;
create policy "owners replace their own avatar"
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
create policy "owners delete their own avatar"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
