# Snaplist

Snap a photo, list it everywhere. An iOS app (Expo) that turns one photo into one
listing, then publishes that listing to our own marketplace and to the seller's
connected channels — eBay, Shopify, and whatever comes after.

## Status

Scaffold plus real auth. Sign-in works against Snaplist's own Supabase project;
the rest of the seller flow is walkable — camera → draft →
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

## Auth and the database

Supabase, in its own project (not the weekly-rivals one - a schema change to one
must not be able to break the other). Sign in with Apple, Google or email; Apple
is first because App Review requires it once any third-party sign-in is offered.
The Google button hides itself until both client IDs are set, so the app never
shows an option that is guaranteed to throw.

After signing in, a seller claims a username before reaching the app. Routing
has three states, not two - signed out, signed in without a name, and in - so
every screen under `(app)` can assume a username exists.

Schema lives in `supabase/migrations/`. The shape that matters:

| table | who can read it |
| --- | --- |
| `profiles` | the owner |
| `connections` | the owner - non-secret, just "eBay is connected" |
| `channel_credentials` | **nobody**: RLS on, zero policies, service role only |
| `listings`, `listing_channels` | the owner |

`channel_credentials` is split out from `connections` on purpose. Postgres RLS is
row-level, not column-level, so the only way to keep a token unreadable by the
app is to put it in a table the app has no policy for.

`connections` has no insert or update policy either: rows appear when the backend
finishes an OAuth round trip, never because the device asked.

### Why usernames need two RPCs

`profiles` is readable only by its owner, so a client-side "is this taken" query
returns nothing and every name looks free. `username_available()` is a
security-definer function that can see across rows and returns exactly one bit.

`claim_username()` exists because checking and then setting would race: two people
can both be told a name is free before either writes. The unique index on
`lower(username)` is the real arbiter; the function just reports its verdict as a
clean `username_taken` error. Case is preserved for display and ignored for
uniqueness, so `Ryan` and `ryan` cannot both exist.

## Shape

```
src/
  app/                    expo-router routes
    (auth)/sign-in.tsx    Apple + Google + email; shown when there is no session
    username.tsx          claim a name; shown when signed in but nameless
    (app)/                tabs: Shop · Sell · Listings · Account
      sell.tsx            the camera; creates a draft on shutter
    draft/[id].tsx        edit the draft, pick channels, publish
  lib/
    auth.tsx              session + profile, Apple/Google/email, username claim
    use-username-check.ts debounced availability, with stale-answer guard
    supabase.ts           client; anon key only, RLS does the real work
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

1. **Backend** (Next.js on Vercel, same stack as weekly-rivals): photo upload,
   `/api/listings/publish`, OAuth callbacks for eBay and Shopify. Auth is done.
2. **Move listings behind `user_id`.** The tables exist and are locked down, but
   `listings.ts` is still AsyncStorage-only, so drafts die with the install. This
   needs photo upload to Supabase Storage first - a draft full of `file://` URIs
   is worthless on a second device.
3. **Vision endpoint**: photo → title, category, condition, suggested price with
   a comp range.
4. **Real eBay adapter**: Sell Inventory API, category suggestion from its
   taxonomy, condition enum mapping.
5. **Real Shopify adapter**: Admin API product create, one default variant.
6. **Our marketplace**: the Shop tab has nothing to render until there is a feed.
7. **Delisting**: when an item sells on one channel, end it on the others. This is
   the feature resellers actually pay for, and it is the reason to own the
   cross-posting rather than bolt it on.

## Conventions

Matches `Projects/ios-app`: Expo SDK 57, expo-router, strict TypeScript, `@/*` →
`src/*`, no typed routes. Light theme on purpose — dark chrome casts a colour
shift over product photos.
