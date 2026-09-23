import { MOCK } from "./api";
import type { Condition } from "./marketplaces";

/**
 * Photo in, draft listing out. This is the whole pitch of the app, and it is the
 * one piece that must run server-side: the model call needs a key, and the same
 * call also wants the pricing history that only the backend has.
 *
 * MOCK returns something plausible so the capture flow can be walked end to end.
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

export async function suggestFromPhoto(_photoUri: string): Promise<Suggestion> {
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

  // Real path: POST the photo to /api/vision/suggest, which runs the model and
  // the comp lookup, and returns this same shape.
  throw new Error("suggestFromPhoto: backend not wired up yet");
}
