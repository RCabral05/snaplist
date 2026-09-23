import type { MarketplaceAdapter } from "./types";

/** Our own marketplace: the permissive one, and the only channel always available. */
export const snaplistAdapter: MarketplaceAdapter = {
  id: "snaplist",
  name: "Snaplist",
  blurb: "Our marketplace. Always on, no connection needed.",
  requiresConnection: false,
  validate: (draft) => {
    const issues = [];
    if (!draft.photos.length) {
      issues.push({ field: "photos", message: "Add at least one photo.", severity: "error" as const });
    }
    if (draft.title.trim().length < 3) {
      issues.push({ field: "title", message: "Give it a title.", severity: "error" as const });
    }
    if (draft.priceCents <= 0) {
      issues.push({ field: "priceCents", message: "Set a price.", severity: "error" as const });
    }
    return issues;
  },
};
