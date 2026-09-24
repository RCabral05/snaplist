import { useCallback, useEffect, useState } from "react";

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
  published_at: string;
};

const SELECT = "id, brand_id, title, price_cents, currency, condition, photos, published_at";
const BRAND_COLUMNS = "id, slug, name, logo_url, bio";

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
    brand: r.brand_id ? (byId.get(r.brand_id) ?? null) : null,
  }));
}

export async function fetchFeed(limit = 50): Promise<ShopItem[]> {
  const { data, error } = await supabase
    .from("listings")
    .select(SELECT)
    .not("published_at", "is", null)
    .order("published_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return withBrands((data ?? []) as ListingRow[]);
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

  return {
    items: answer?.items ?? [],
    isLoading: answer === null || answer.attempt !== attempt,
    refresh,
  };
}

export function useFeed() {
  return useItems(useCallback(() => fetchFeed(), []));
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

  return { brand, ...useItems(load) };
}
