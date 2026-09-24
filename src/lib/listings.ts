import AsyncStorage from "@react-native-async-storage/async-storage";
import * as Crypto from "expo-crypto";
import { useCallback, useEffect, useState } from "react";

import { MOCK, api } from "./api";
import type { ChannelId, ChannelListing, Condition, ListingDraft } from "./marketplaces";
import { removeListingPhotos } from "./photos";
import { supabase } from "./supabase";

/**
 * Drafts live in Postgres, one row per listing, guarded by the owner-only policy
 * on public.listings. They used to live in AsyncStorage, which meant a draft died
 * with the install and could never reach a second device.
 *
 * Per-channel publish state is still local. public.listing_channels has no insert
 * policy for the device on purpose - those rows are written by the backend after a
 * real publish attempt - so until that backend exists the mock states have nowhere
 * legitimate to go but here.
 */
const STATUS_KEY = "snaplist.channel-listings.v1";

type Row = {
  id: string;
  title: string;
  description: string;
  price_cents: number;
  currency: string;
  condition: Condition;
  quantity: number;
  category: string | null;
  brand: string | null;
  photos: string[];
  channels: string[];
  created_at: string;
  updated_at: string;
};

const listeners = new Set<() => void>();
const emit = () => listeners.forEach((l) => l());

let draftCache: ListingDraft[] | null = null;
let statusCache: ChannelListing[] | null = null;

const now = () => new Date().toISOString();

const toDraft = (r: Row): ListingDraft => ({
  id: r.id,
  photos: r.photos ?? [],
  title: r.title,
  description: r.description,
  priceCents: r.price_cents,
  currency: r.currency,
  condition: r.condition,
  quantity: r.quantity,
  category: r.category ?? undefined,
  brand: r.brand ?? undefined,
  channels: (r.channels ?? []) as ChannelId[],
  createdAt: r.created_at,
  updatedAt: r.updated_at,
});

const toRow = (d: ListingDraft, userId: string) => ({
  id: d.id,
  user_id: userId,
  title: d.title,
  description: d.description,
  price_cents: d.priceCents,
  currency: d.currency,
  condition: d.condition,
  quantity: d.quantity,
  category: d.category ?? null,
  brand: d.brand ?? null,
  photos: d.photos,
  channels: d.channels,
  updated_at: now(),
});

async function requireUid(): Promise<string> {
  const { data } = await supabase.auth.getUser();
  if (!data.user) throw new Error("Not signed in.");
  return data.user.id;
}

/**
 * A client-generated uuid, not a server default. The camera screen needs an id
 * the instant the shutter fires so it can name the photo's folder and push the
 * editor, both of which happen before any insert has come back.
 */
export function emptyDraft(photos: string[] = []): ListingDraft {
  return {
    id: Crypto.randomUUID(),
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
  const uid = await requireUid();
  const next = { ...draft, updatedAt: now() };

  const { error } = await supabase.from("listings").upsert(toRow(next, uid), { onConflict: "id" });
  if (error) throw error;

  draftCache = [next, ...(draftCache ?? []).filter((d) => d.id !== draft.id)];
  emit();
  return next;
}

export async function getDraft(id: string): Promise<ListingDraft | undefined> {
  const local = draftCache?.find((d) => d.id === id);
  if (local) return local;

  const { data, error } = await supabase.from("listings").select("*").eq("id", id).maybeSingle();
  if (error || !data) return undefined;
  return toDraft(data as Row);
}

export async function removeDraft(id: string) {
  const uid = await requireUid();

  // Photos first. Deleting the row loses the only record of which objects
  // belonged to it, and orphaned files in a private bucket are invisible.
  await removeListingPhotos(uid, id).catch(() => {});

  const { error } = await supabase.from("listings").delete().eq("id", id);
  if (error) throw error;

  draftCache = (draftCache ?? []).filter((d) => d.id !== id);
  statusCache = (statusCache ?? []).filter((c) => c.listingId !== id);
  await saveStatuses(statusCache);
  emit();
}

async function loadDrafts(): Promise<ListingDraft[]> {
  const { data, error } = await supabase
    .from("listings")
    .select("*")
    .order("updated_at", { ascending: false });
  if (error) throw error;
  draftCache = (data as Row[]).map(toDraft);
  return draftCache;
}

async function loadStatuses(): Promise<ChannelListing[]> {
  if (statusCache) return statusCache;
  const raw = await AsyncStorage.getItem(STATUS_KEY);
  statusCache = raw ? (JSON.parse(raw) as ChannelListing[]) : [];
  return statusCache;
}

async function saveStatuses(next: ChannelListing[]) {
  statusCache = next;
  await AsyncStorage.setItem(STATUS_KEY, JSON.stringify(next));
}

/**
 * Publish fans the draft out to every chosen channel. It is deliberately one
 * backend call: partial failure is normal (eBay rejects, Shopify accepts), so the
 * backend returns a per-channel result and the app shows the mixed outcome rather
 * than pretending the publish was all-or-nothing.
 */
export async function publish(draft: ListingDraft): Promise<ChannelListing[]> {
  const existing = await loadStatuses();

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

  await saveStatuses([...existing.filter((c) => c.listingId !== draft.id), ...results]);
  emit();
  return results;
}

export function useListings() {
  const [drafts, setDrafts] = useState<ListingDraft[]>(draftCache ?? []);
  const [channels, setChannels] = useState<ChannelListing[]>(statusCache ?? []);
  const [isLoading, setLoading] = useState(!draftCache);

  const refresh = useCallback(() => {
    Promise.all([loadDrafts(), loadStatuses()])
      .then(([d, c]) => {
        setDrafts([...d]);
        setChannels([...c]);
      })
      .catch(() => {
        // An offline Listings tab shows what is cached rather than an error.
      })
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    refresh();
    const listener = () => {
      setDrafts([...(draftCache ?? [])]);
      setChannels([...(statusCache ?? [])]);
    };
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
    };
  }, [refresh]);

  const channelsFor = useCallback(
    (listingId: string) => channels.filter((c) => c.listingId === listingId),
    [channels],
  );

  return { drafts, channels, channelsFor, isLoading, refresh };
}

export const money = (cents: number, currency = "USD") =>
  new Intl.NumberFormat("en-US", { style: "currency", currency }).format(cents / 100);

export const parseMoney = (input: string): number => {
  const n = Number(input.replace(/[^0-9.]/g, ""));
  return Number.isFinite(n) ? Math.round(n * 100) : 0;
};

export type { ChannelId, ChannelListing, ListingDraft };
