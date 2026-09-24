-- Which channels the seller picked, before anything is published.
--
-- listing_channels is the wrong home for this: it records what happened on each
-- channel, it is written only by the backend, and the device has no insert
-- policy for it on purpose. The selection is a draft-time intention, so it
-- belongs on the draft.

alter table public.listings
  add column if not exists channels text[] not null default '{snaplist}';
