import AsyncStorage from "@react-native-async-storage/async-storage";
import { useCallback, useEffect, useState } from "react";

import { MOCK, api } from "./api";
import type { ChannelId, ChannelListing, ListingDraft } from "./marketplaces";

/**
 * Drafts live on the device until they are published; published listings are
 * mirrored here so the Listings tab works offline and on a cold start. The
 * backend stays the source of truth for anything with a remote id.
 */
const KEY = "snaplist.listings.v1";
const STATUS_KEY = "snaplist.channel-listings.v1";

type Store = { drafts: ListingDraft[]; channels: ChannelListing[] };

let cache: Store | null = null;
const listeners = new Set<() => void>();
const emit = () => listeners.forEach((l) => l());

const now = () => new Date().toISOString();
const newId = () => Math.random().toString(36).slice(2, 10) + Date.now().toString(36);

async function load(): Promise<Store> {
  if (cache) return cache;
  const [rawDrafts, rawChannels] = await Promise.all([
    AsyncStorage.getItem(KEY),
    AsyncStorage.getItem(STATUS_KEY),
  ]);
  cache = {
    drafts: rawDrafts ? (JSON.parse(rawDrafts) as ListingDraft[]) : [],
    channels: rawChannels ? (JSON.parse(rawChannels) as ChannelListing[]) : [],
  };
  return cache;
}

async function save(next: Store) {
  cache = next;
  await Promise.all([
    AsyncStorage.setItem(KEY, JSON.stringify(next.drafts)),
    AsyncStorage.setItem(STATUS_KEY, JSON.stringify(next.channels)),
  ]);
  emit();
}

export function emptyDraft(photos: string[] = []): ListingDraft {
  return {
    id: newId(),
    photos,
    title: "",
    description: "",
    priceCents: 0,
    currency: "USD",
    condition: "good",
    quantity: 1,
    channels: ["snaplist"],
    createdAt: now(),
    updatedAt: now(),
  };
}

export async function putDraft(draft: ListingDraft) {
  const store = await load();
  const next = { ...draft, updatedAt: now() };
  await save({
    ...store,
    drafts: [next, ...store.drafts.filter((d) => d.id !== draft.id)],
  });
  return next;
}

export async function getDraft(id: string): Promise<ListingDraft | undefined> {
  return (await load()).drafts.find((d) => d.id === id);
}

export async function removeDraft(id: string) {
  const store = await load();
  await save({
    drafts: store.drafts.filter((d) => d.id !== id),
    channels: store.channels.filter((c) => c.listingId !== id),
  });
}

/**
 * Publish fans the draft out to every chosen channel. It is deliberately one
 * backend call: partial failure is normal (eBay rejects, Shopify accepts), so the
 * backend returns a per-channel result and the app shows the mixed outcome rather
 * than pretending the publish was all-or-nothing.
 */
export async function publish(draft: ListingDraft): Promise<ChannelListing[]> {
  const store = await load();

  const results: ChannelListing[] = MOCK
    ? draft.channels.map((channel) => ({
        listingId: draft.id,
        channel,
        state: channel === "snaplist" ? ("live" as const) : ("pending" as const),
        message: channel === "snaplist" ? undefined : "Waiting on the backend.",
        updatedAt: now(),
      }))
    : await api<ChannelListing[]>("/api/listings/publish", {
        method: "POST",
        body: JSON.stringify(draft),
      });

  await save({
    ...store,
    channels: [
      ...store.channels.filter((c) => c.listingId !== draft.id),
      ...results,
    ],
  });
  return results;
}

export function useListings() {
  const [store, setStore] = useState<Store>(cache ?? { drafts: [], channels: [] });
  const [isLoading, setLoading] = useState(!cache);

  const refresh = useCallback(() => {
    load().then((s) => {
      setStore({ drafts: [...s.drafts], channels: [...s.channels] });
      setLoading(false);
    });
  }, []);

  useEffect(() => {
    refresh();
    const listener = () =>
      setStore({ drafts: [...(cache?.drafts ?? [])], channels: [...(cache?.channels ?? [])] });
    listeners.add(listener);
    return () => { listeners.delete(listener); };
  }, [refresh]);

  const channelsFor = useCallback(
    (listingId: string) => store.channels.filter((c) => c.listingId === listingId),
    [store.channels],
  );

  return { ...store, channelsFor, isLoading, refresh };
}

export const money = (cents: number, currency = "USD") =>
  new Intl.NumberFormat("en-US", { style: "currency", currency }).format(cents / 100);

export const parseMoney = (input: string): number => {
  const n = Number(input.replace(/[^0-9.]/g, ""));
  return Number.isFinite(n) ? Math.round(n * 100) : 0;
};

export type { ChannelId, ChannelListing, ListingDraft };
