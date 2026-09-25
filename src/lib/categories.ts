import type { SFSymbol } from "expo-symbols";

/**
 * The fixed taxonomy.
 *
 * Free-text categories were useless for filtering - four listings produced
 * "Beverages", "Shoes & Sneakers", "Shoes" and "Gaming", and no two of them
 * would ever match a filter. A closed set is what makes browsing possible, and
 * the same set is enforced by a check constraint on listings.category_slug so a
 * bad value cannot arrive from anywhere else either.
 *
 * Deliberately short. Ten broad buckets a seller can pick from without thinking
 * beats forty precise ones they get wrong; `category` still carries the specific
 * description underneath ("Running shoes" under `shoes`).
 */
export type CategorySlug =
  | "clothing"
  | "shoes"
  | "electronics"
  | "home"
  | "toys"
  | "sports"
  | "books"
  | "beauty"
  | "collectibles"
  | "other";

export type Category = { slug: CategorySlug; label: string; icon: SFSymbol };

export const CATEGORIES: Category[] = [
  { slug: "clothing", label: "Clothing", icon: "tshirt" },
  { slug: "shoes", label: "Shoes", icon: "figure.walk" },
  { slug: "electronics", label: "Electronics", icon: "desktopcomputer" },
  { slug: "home", label: "Home", icon: "house" },
  { slug: "toys", label: "Toys & Games", icon: "gamecontroller" },
  { slug: "sports", label: "Sports", icon: "sportscourt" },
  { slug: "books", label: "Books & Media", icon: "book" },
  { slug: "beauty", label: "Beauty", icon: "sparkles" },
  { slug: "collectibles", label: "Collectibles", icon: "star" },
  { slug: "other", label: "Other", icon: "shippingbox" },
];

const bySlug = new Map(CATEGORIES.map((c) => [c.slug, c]));

export const categoryFor = (slug?: string | null): Category | undefined =>
  slug ? bySlug.get(slug as CategorySlug) : undefined;

export const categoryLabel = (slug?: string | null): string =>
  categoryFor(slug)?.label ?? "Other";
