-- Real categories, and a way to feature something.
--
-- `category` was free text straight out of the model, which gave us "Beverages",
-- "Shoes & Sneakers", "Shoes" and "Gaming" for four items - useless for a filter,
-- because no two listings agree on what a category is. category_slug is a fixed
-- set the model must choose from, and the free-text column stays as the specific
-- description underneath it ("Running shoes" under `shoes`).
--
-- The constraint lives here rather than only in TypeScript so a bad slug cannot
-- reach the table from a seed script, a backfill, or a future second client.

alter table public.listings add column if not exists category_slug text;

alter table public.listings drop constraint if exists listings_category_slug_known;
alter table public.listings add constraint listings_category_slug_known
  check (category_slug is null or category_slug in (
    'clothing', 'shoes', 'electronics', 'home', 'toys',
    'sports', 'books', 'beauty', 'collectibles', 'other'
  ));

-- Curation is a decision someone makes, not something derived from recency or
-- price - both of which would let a seller feature themselves by listing again.
alter table public.listings add column if not exists is_featured boolean not null default false;

create index if not exists listings_category_idx
  on public.listings (category_slug, published_at desc)
  where published_at is not null;

create index if not exists listings_featured_idx
  on public.listings (published_at desc)
  where published_at is not null and is_featured;
