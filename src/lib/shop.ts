import { useCallback, useEffect, useMemo, useState } from "react";

import type { Condition } from "./marketplaces";
import { supabase } from "./supabase";

/**
 * The buyer side. Everything here reads rows a seller has published - listings
 * with a published_at, which is all the public read policy lets through - so
 * nothing in this file can see a draft.
 *
 * Listings belong to a brand, not to a person, and the brand is what a buyer
 * sees. public_brands is a view for the same reason public_profiles is: a read
 * policy on the table would expose owner_id and map a storefront to a human.
 */

export type ShopBrand = {
  id: string;
  slug: string;
  name: string;
  logo_url: string | null;
  bio: string | null;
};

export type ShopItem = {
  id: string;
  title: string;
  priceCents: number;
  currency: string;
  condition: Condition;
  /** Storage object path; the card signs it for display. */
  photo?: string;
  publishedAt: string;
  categorySlug?: string;
  isFeatured: boolean;
  brand: ShopBrand | null;
};

type ListingRow = {
  id: string;
  brand_id: string | null;
  title: string;
  price_cents: number;
  currency: string;
  condition: Condition;
  photos: string[] | null;
  category_slug: string | null;
  is_featured: boolean;
  published_at: string;
};

const SELECT =
  "id, brand_id, title, price_cents, currency, condition, photos, category_slug, is_featured, published_at";
const BRAND_COLUMNS = "id, slug, name, logo_url, bio";

/** Shared identity for "nothing yet", so an empty result is not a new array. */
const NO_ITEMS: ShopItem[] = [];

/**
 * Brands are fetched separately rather than embedded: public_brands is a view
 * and carries no foreign key, so PostgREST cannot infer the relationship. Two
 * small queries beat fighting the embed syntax.
 */
async function withBrands(rows: ListingRow[]): Promise<ShopItem[]> {
  const ids = [...new Set(rows.map((r) => r.brand_id).filter(Boolean))] as string[];
  const byId = new Map<string, ShopBrand>();

  if (ids.length) {
    const { data } = await supabase.from("public_brands").select(BRAND_COLUMNS).in("id", ids);
    for (const b of (data ?? []) as ShopBrand[]) byId.set(b.id, b);
  }

  return rows.map((r) => ({
    id: r.id,
    title: r.title,
    priceCents: r.price_cents,
    currency: r.currency,
    condition: r.condition,
    photo: r.photos?.[0],
    publishedAt: r.published_at,
    categorySlug: r.category_slug ?? undefined,
    isFeatured: r.is_featured,
    brand: r.brand_id ? (byId.get(r.brand_id) ?? null) : null,
  }));
}

export type FeedOptions = { query?: string; category?: string | null; limit?: number };

export async function fetchFeed({
  query = "",
  category = null,
  limit = 60,
}: FeedOptions = {}): Promise<ShopItem[]> {
  let q = supabase
    .from("listings")
    .select(SELECT)
    .not("published_at", "is", null)
    .order("published_at", { ascending: false })
    .limit(limit);

  if (category) q = q.eq("category_slug", category);

  // Filtered in Postgres, not in the client. A feed small enough to filter on
  // the device today will not stay that way, and the index is already there.
  // Commas and parentheses would be read as PostgREST syntax, so they go.
  const term = query.trim().replace(/[,()]/g, "");
  if (term) {
    q = q.or(`title.ilike.%${term}%,brand.ilike.%${term}%,category.ilike.%${term}%`);
  }

  const { data, error } = await q;
  if (error) throw error;
  return withBrands((data ?? []) as ListingRow[]);
}

/**
 * Curated, not derived. Ordering by recency or price would let any seller
 * feature themselves just by listing again.
 */
export async function fetchFeatured(limit = 8): Promise<ShopItem[]> {
  const { data, error } = await supabase
    .from("listings")
    .select(SELECT)
    .not("published_at", "is", null)
    .eq("is_featured", true)
    .order("published_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return withBrands((data ?? []) as ListingRow[]);
}

/** One listing, with the description the grid does not need to carry. */
export type ShopItemDetail = ShopItem & { description: string; photos: string[] };

export async function fetchItem(id: string): Promise<ShopItemDetail | null> {
  const { data, error } = await supabase
    .from("listings")
    .select(SELECT + ", description, category")
    .eq("id", id)
    .not("published_at", "is", null)
    .maybeSingle();
  if (error || !data) return null;

  // Through unknown: the select string is built by concatenation, so supabase-js
  // cannot infer a row shape from it and falls back to its error type.
  const row = data as unknown as ListingRow & { description: string };
  const [item] = await withBrands([row]);
  return item ? { ...item, description: row.description ?? "", photos: row.photos ?? [] } : null;
}

export function useItem(id?: string) {
  const [item, setItem] = useState<ShopItemDetail | null>(null);
  const [isLoading, setLoading] = useState(true);

  useEffect(() => {
    if (!id) return;
    let alive = true;
    fetchItem(id)
      .then((found) => {
        if (!alive) return;
        setItem(found);
        setLoading(false);
      })
      .catch(() => {
        if (alive) setLoading(false);
      });
    return () => {
      alive = false;
    };
  }, [id]);

  return { item, isLoading };
}

export async function fetchBrandBySlug(slug: string): Promise<ShopBrand | null> {
  const { data } = await supabase
    .from("public_brands")
    .select(BRAND_COLUMNS)
    .ilike("slug", slug)
    .maybeSingle();
  return (data as ShopBrand | null) ?? null;
}

export async function fetchBrandListings(brandId: string): Promise<ShopItem[]> {
  const { data, error } = await supabase
    .from("listings")
    .select(SELECT)
    .eq("brand_id", brandId)
    .not("published_at", "is", null)
    .order("published_at", { ascending: false });
  if (error) throw error;
  return withBrands((data ?? []) as ListingRow[]);
}

/**
 * Shared loading shape for the feed and for one brand's storefront.
 *
 * The result is tagged with the attempt it answers, so "loading" is derived from
 * whether the newest attempt has come back rather than being a flag something
 * has to remember to set. Refreshing therefore keeps the previous items on
 * screen instead of blanking the list while the next page is in flight.
 */
function useItems(load: () => Promise<ShopItem[]>) {
  const [attempt, setAttempt] = useState(0);
  const [answer, setAnswer] = useState<{ attempt: number; items: ShopItem[] } | null>(null);

  useEffect(() => {
    let alive = true;
    load()
      .then((rows) => {
        if (alive) setAnswer({ attempt, items: rows });
      })
      .catch(() => {
        if (alive) setAnswer({ attempt, items: [] });
      });
    return () => {
      alive = false;
    };
  }, [load, attempt]);

  const refresh = useCallback(() => setAttempt((n) => n + 1), []);

  const items = answer?.items ?? NO_ITEMS;
  const isLoading = answer === null || answer.attempt !== attempt;

  // Memoised, and the empty case is a shared constant rather than a fresh [].
  // A caller who puts this result in a dependency array - which is an easy thing
  // to do - then gets an effect that runs once, not one that runs every render.
  // When that effect's job is to refetch, the difference is an infinite loop.
  return useMemo(() => ({ items, isLoading, refresh }), [items, isLoading, refresh]);
}

export function useFeed({ query = "", category = null }: FeedOptions = {}) {
  return useItems(useCallback(() => fetchFeed({ query, category }), [query, category]));
}

export function useFeatured() {
  return useItems(useCallback(() => fetchFeatured(), []));
}

export function useBrandShop(slug?: string) {
  const [brand, setBrand] = useState<ShopBrand | null>(null);

  const load = useCallback(async () => {
    if (!slug) return [];
    const found = await fetchBrandBySlug(slug);
    setBrand(found);
    if (!found) return [];
    return fetchBrandListings(found.id);
  }, [slug]);

  const state = useItems(load);
  return useMemo(() => ({ brand, ...state }), [brand, state]);
}
