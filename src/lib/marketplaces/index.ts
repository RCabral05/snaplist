import { ebayAdapter } from "./ebay";
import { shopifyAdapter } from "./shopify";
import { snaplistAdapter } from "./snaplist";
import type { ChannelId, FieldIssue, ListingDraft, MarketplaceAdapter } from "./types";

export * from "./types";

/** Registry order is display order: ours first, then the connected channels. */
export const adapters: MarketplaceAdapter[] = [snaplistAdapter, ebayAdapter, shopifyAdapter];

export const adapterFor = (id: ChannelId): MarketplaceAdapter => {
  const found = adapters.find((a) => a.id === id);
  if (!found) throw new Error("No adapter for channel " + id);
  return found;
};

/** Pre-flight across every channel the draft is aimed at, tagged by channel. */
export const validateDraft = (draft: ListingDraft): (FieldIssue & { channel: ChannelId })[] =>
  draft.channels.flatMap((id) =>
    adapterFor(id)
      .validate(draft)
      .map((issue) => ({ ...issue, channel: id })),
  );

export const canPublish = (draft: ListingDraft): boolean =>
  validateDraft(draft).every((issue) => issue.severity !== "error");
