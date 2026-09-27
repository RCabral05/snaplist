-- Make the username grants true.
--
-- 0013 did "revoke all from public" then "grant execute to authenticated", which
-- reads as authenticated-only and is not. Supabase ships ALTER DEFAULT
-- PRIVILEGES granting EXECUTE on new functions in public to anon, authenticated
-- and service_role, and that applies at creation - after the revoke. Both
-- functions ended up callable by anon.
--
-- Not a hole: claim_username checks auth.uid() and raises not_authenticated, so
-- a signed-out caller gets an error rather than a name. But a grant that says
-- one thing and does another is how the next person gets surprised.
--
-- If a pre-signup availability check is ever wanted, grant username_available
-- back to anon deliberately rather than by inheritance.

revoke execute on function public.username_available(text) from anon;
revoke execute on function public.claim_username(text) from anon;
revoke execute on function public.username_reserved(text) from anon;
