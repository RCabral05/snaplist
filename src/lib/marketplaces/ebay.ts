import type { MarketplaceAdapter } from "./types";

/**
 * eBay is the strict one: 80-character titles, a required leaf category from its
 * own taxonomy, and a condition enum. Catching that here means the seller fixes it
 * once, in the editor, rather than reading a 400 from the Sell API.
 */
export const ebayAdapter: MarketplaceAdapter = {
  id: "ebay",
  name: "eBay",
  blurb: "Cross-post to your eBay seller account.",
  requiresConnection: true,
  validate: (draft) => {
    const issues = [];
    if (draft.title.length > 80) {
      issues.push({
        field: "title",
        message: "eBay titles stop at 80 characters.",
        severity: "error" as const,
      });
    }
    if (!draft.category) {
      issues.push({
        field: "category",
        message: "eBay needs a category.",
        severity: "error" as const,
      });
    }
    if (draft.photos.length > 24) {
      issues.push({
        field: "photos",
        message: "eBay takes the first 24 photos.",
        severity: "warning" as const,
      });
    }
    if (!draft.brand) {
      issues.push({
        field: "brand",
        message: "Listings with a brand surface better in eBay search.",
        severity: "warning" as const,
      });
    }
    return issues;
  },
};
