-- How sure the model was.
--
-- The vision endpoint already returns a confidence and the app threw it away, so
-- a listing the model openly guessed at filled the form exactly as confidently as
-- one it recognised. The seller had no way to tell the difference, which is the
-- worst version of this feature: wrong titles that look reviewed.
--
-- It lives on the row rather than in memory because a seller can photograph five
-- things and come back to them later, by which point an in-session flag is long
-- gone. Null means no suggestion was applied, or the seller has since edited the
-- title - either way there is nothing left to caveat.

alter table public.listings add column if not exists suggested_confidence real;
