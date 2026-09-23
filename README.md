# Snaplist

Snap a photo, list it everywhere. An iOS app (Expo) that turns one photo into one
listing, then publishes that listing to our own marketplace and to the seller's
connected channels — eBay, Shopify, and whatever comes after.

## Status

Scaffold. The app runs and the whole seller flow is walkable — camera → draft →
channel picker → publish → status list — but there is no backend yet, so
`MOCK` is on: the model suggestion returns a placeholder and publishing resolves
locally. Everything below the "What's next" line is not built.

## Running it

```
npm install
npx expo start
```

Expo Go will not work (custom native modules). Build a dev client:

```
npx eas build --profile development --platform ios
```

## Shape

```
src/
  app/                    expo-router routes
    (app)/                tabs: Shop · Sell · Listings · Account
      sell.tsx            the camera; creates a draft on shutter
    draft/[id].tsx        edit the draft, pick channels, publish
  lib/
    marketplaces/         the adapter layer (see below)
    listings.ts           draft store + publish, AsyncStorage-backed
    connections.ts        which channels this seller has connected
    vision.ts             photo → suggested title/price/category
    api.ts                backend client; MOCK when no API_URL is set
  components/
  theme.ts
```

## The adapter layer

One listing, many channels. `ListingDraft` is our own neutral shape; each channel
gets a `MarketplaceAdapter` that knows what that channel demands and how to say
what is missing. Adapters run **locally, before publish** — so the seller sees
"eBay needs a category" while they are still typing, instead of a 400 from the
Sell API thirty seconds later.

Adding a channel is: one file in `src/lib/marketplaces/`, one entry in the
registry, one handler on the backend. Nothing else in the app changes.

Adapters deliberately do **not** call marketplace APIs.

### Why the app cannot hold marketplace keys

An iOS binary is readable. Anything shipped inside it — an eBay app secret, a
Shopify access token, a model API key — is public the moment it ships. So:

- The device stores *the fact* that a channel is connected, never the token.
- OAuth is a browser round trip that finishes on the backend, which stores the
  token against the seller's account.
- Publishing is one call to our backend, which fans out to each channel.
- The photo→listing model call also runs server-side, because it needs a key and
  because the pricing comps live there anyway.

This is the main architectural constraint on the project and it is why the next
piece of work is a backend, not more screens.

## Publishing is not all-or-nothing

eBay can reject while Shopify accepts. `publish()` returns a `ChannelListing[]` —
one row per channel with its own state (`draft · pending · live · failed · ended`)
— and the UI shows the mixed outcome instead of pretending a publish either
worked or didn't.

## What's next

1. **Backend** (Next.js on Vercel, same stack as weekly-rivals): auth, photo
   upload, `/api/listings/publish`, OAuth callbacks for eBay and Shopify.
2. **Vision endpoint**: photo → title, category, condition, suggested price with
   a comp range.
3. **Real eBay adapter**: Sell Inventory API, category suggestion from its
   taxonomy, condition enum mapping.
4. **Real Shopify adapter**: Admin API product create, one default variant.
5. **Our marketplace**: the Shop tab has nothing to render until there is a feed.
6. **Delisting**: when an item sells on one channel, end it on the others. This is
   the feature resellers actually pay for, and it is the reason to own the
   cross-posting rather than bolt it on.

## Conventions

Matches `Projects/ios-app`: Expo SDK 57, expo-router, strict TypeScript, `@/*` →
`src/*`, no typed routes. Light theme on purpose — dark chrome casts a colour
shift over product photos.
