import type { MarketplaceAdapter } from "./types";

/**
 * Shopify is a storefront rather than a marketplace: the draft becomes a product
 * with one default variant. It is relaxed about metadata and strict about nothing,
 * which makes it the easiest second channel to turn on.
 */
export const shopifyAdapter: MarketplaceAdapter = {
  id: "shopify",
  name: "Shopify",
  blurb: "Push to your own Shopify store as a product.",
  requiresConnection: true,
  validate: (draft) => {
    const issues = [];
    if (!draft.description.trim()) {
      issues.push({
        field: "description",
        message: "Shopify products read better with a description.",
        severity: "warning" as const,
      });
    }
    if (draft.quantity < 1) {
      issues.push({
        field: "quantity",
        message: "Set a quantity of at least 1.",
        severity: "error" as const,
      });
    }
    return issues;
  },
};
