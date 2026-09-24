import { MOCK, api } from "./api";
import type { Condition } from "./marketplaces";
import { supabase } from "./supabase";

/**
 * Photo in, draft listing out. This is the whole pitch of the app, and it is the
 * one piece that must run server-side: the model call needs a key, and anything
 * EXPO_PUBLIC_* is compiled into the binary where anyone can read it.
 *
 * MOCK returns something plausible so the capture flow can be walked end to end
 * without a backend. Its values are fixed - a "suggestion" of "Untitled item" at
 * $25.00 is the mock talking, not the model.
 */
export type Suggestion = {
  title: string;
  description: string;
  category?: string;
  brand?: string;
  condition: Condition;
  /** What we think it sells for, in cents, with a range to show as a hint. */
  priceCents: number;
  priceLowCents?: number;
  priceHighCents?: number;
  confidence: number;
};

/**
 * Takes the Storage object path, not the local file. The photo is already
 * uploaded by the time we ask, and sending a path instead of a few megabytes of
 * base64 keeps the request small enough that no serverless body limit is in play.
 */
export async function suggestFromPhoto(photoPath: string): Promise<Suggestion> {
  if (MOCK) {
    await new Promise((r) => setTimeout(r, 900));
    return {
      title: "Untitled item",
      description: "",
      condition: "good",
      priceCents: 2500,
      priceLowCents: 1800,
      priceHighCents: 3500,
      confidence: 0,
    };
  }

  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new Error("Not signed in.");

  return api<Suggestion>("/api/vision/suggest", {
    method: "POST",
    token,
    body: JSON.stringify({ path: photoPath }),
  });
}
