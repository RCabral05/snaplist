/**
 * One listing, many channels.
 *
 * A ListingDraft is the app's own neutral shape. Every channel (our marketplace,
 * eBay, Shopify, whatever comes next) gets an adapter that knows three things:
 * what it needs that the neutral draft may not have, how to say what is missing,
 * and what its own listing looks like once published.
 *
 * Adapters deliberately do NOT call marketplace APIs. Publishing goes through our
 * backend, which is the only place the OAuth tokens exist. See README.
 */

export type ChannelId = "snaplist" | "ebay" | "shopify";

export type Condition = "new" | "like_new" | "good" | "fair" | "parts";

export type ListingDraft = {
  id: string;
  /** The brand it is sold under. Every listing has one; buyers see the brand. */
  brandId: string;
  /** Local file URIs until the photo has uploaded; then Storage object paths. */
  photos: string[];
  title: string;
  description: string;
  /** Minor units (cents), so we never do float maths on money. */
  priceCents: number;
  currency: string;
  condition: Condition;
  quantity: number;
  /** Free-text for now; each adapter maps it onto its own taxonomy. */
  category?: string;
  brand?: string;
  /**
   * How sure the model was about the suggestion that filled this in, 0 to 1.
   * Undefined once the seller has edited the title, or if nothing was suggested.
   */
  suggestedConfidence?: number;
  /**
   * When it went live on our own marketplace, or undefined while it is a draft.
   * This is the fact - not the per-device channel cache, which only knows what
   * this install happened to do.
   */
  publishedAt?: string;
  /** Channels the seller has chosen to publish to. */
  channels: ChannelId[];
  createdAt: string;
  updatedAt: string;
};

export type PublishState = "draft" | "pending" | "live" | "failed" | "ended";

/** Where one draft stands on one channel. Keyed by listing id + channel id. */
export type ChannelListing = {
  listingId: string;
  channel: ChannelId;
  state: PublishState;
  /** The channel's own id for this listing, once it exists. */
  remoteId?: string;
  remoteUrl?: string;
  message?: string;
  updatedAt: string;
};

/** A field the channel needs before it will accept the draft. */
export type FieldIssue = {
  field: keyof ListingDraft | string;
  message: string;
  /** blocking issues stop publish; warnings are shown but do not block. */
  severity: "error" | "warning";
};

export type MarketplaceAdapter = {
  id: ChannelId;
  name: string;
  /** Shown on the connections screen. */
  blurb: string;
  /** Our own marketplace needs no OAuth; the others do. */
  requiresConnection: boolean;
  /**
   * Local pre-flight. Runs before we ever hit the network so the seller sees
   * "eBay needs a category" while they are still editing, not after publish.
   */
  validate: (draft: ListingDraft) => FieldIssue[];
};
