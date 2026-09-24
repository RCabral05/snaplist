import { useCallback, useEffect, useState } from "react";

import type { Condition } from "./marketplaces";
import { supabase } from "./supabase";

/**
 * The buyer side. Everything here reads rows the seller has published - listings
 * with a published_at, which is the only thing the public read policy lets
 * through - so nothing in this file can see a draft it does not own.
 *
 * Snaplist has one storefront per seller and the profile is that storefront, so
 * a "shop" is just a seller's published listings. There is no brand table to
 * join through; if sellers ever need more than one shop, listings already carry
 * user_id and backfilling a brand_id from it is mechanical.
 */

export type Seller = {
  id: string;
  username: string | null;
  display_name: string;
  avatar_url: string | null;
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
  seller: Seller | null;
};

type ListingRow = {
  id: string;
  user_id: string;
  title: string;
  price_cents: number;
  currency: string;
  condition: Condition;
  photos: string[] | null;
  published_at: string;
};

const SELECT = "id, user_id, title, price_cents, currency, condition, photos, published_at";

/**
 * Sellers are fetched separately rather than embedded. public_profiles is a view
 * and carries no foreign key, so PostgREST cannot infer the relationship - two
 * small queries are more predictable than fighting the embed syntax.
 */
async function withSellers(rows: ListingRow[]): Promise<ShopItem[]> {
  const ids = [...new Set(rows.map((r) => r.user_id))];
  const byId = new Map<string, Seller>();

  if (ids.length) {
    const { data } = await supabase
      .from("public_profiles")
      .select("id, username, display_name, avatar_url")
      .in("id", ids);
    for (const p of (data ?? []) as Seller[]) byId.set(p.id, p);
  }

  return rows.map((r) => ({
    id: r.id,
    title: r.title,
    priceCents: r.price_cents,
    currency: r.currency,
    condition: r.condition,
    photo: r.photos?.[0],
    publishedAt: r.published_at,
    seller: byId.get(r.user_id) ?? null,
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
  return withSellers((data ?? []) as ListingRow[]);
}

export async function fetchSeller(username: string): Promise<Seller | null> {
  const { data } = await supabase
    .from("public_profiles")
    .select("id, username, display_name, avatar_url")
    .ilike("username", username)
    .maybeSingle();
  return (data as Seller | null) ?? null;
}

export async function fetchSellerListings(sellerId: string): Promise<ShopItem[]> {
  const { data, error } = await supabase
    .from("listings")
    .select(SELECT)
    .eq("user_id", sellerId)
    .not("published_at", "is", null)
    .order("published_at", { ascending: false });
  if (error) throw error;
  return withSellers((data ?? []) as ListingRow[]);
}

/**
 * Shared loading shape for the feed and for one seller's shop.
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

export function useSellerShop(username?: string) {
  const [seller, setSeller] = useState<Seller | null>(null);

  const load = useCallback(async () => {
    if (!username) return [];
    const found = await fetchSeller(username);
    setSeller(found);
    if (!found) return [];
    return fetchSellerListings(found.id);
  }, [username]);

  return { seller, ...useItems(load) };
}
