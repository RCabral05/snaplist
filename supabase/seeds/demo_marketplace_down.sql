-- Removes everything demo_marketplace.sql creates.
--
-- The listings and brands go with the users: listings.user_id and brands.owner_id
-- both cascade from auth.users, as does profiles. Deleting the five seed users is
-- therefore enough, and doing it that way means a row added later under a seed
-- brand disappears too rather than being orphaned.

delete from auth.users
 where id in (
   '00000000-0000-4000-8000-000000000001',
   '00000000-0000-4000-8000-000000000002',
   '00000000-0000-4000-8000-000000000003',
   '00000000-0000-4000-8000-000000000004',
   '00000000-0000-4000-8000-000000000005'
 );
