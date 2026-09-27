# Snaplist

An iOS app (Expo) that signs you in and shows you your profile. That is the whole
app right now — the marketplace it used to be was removed on 2026-09-27 and is
recoverable from git history if it is ever wanted back.

## Running it

```
npm install
npx expo start --dev-client
```

Expo Go will not work (custom native modules). Build a dev client:

```
npx eas build --profile development --platform ios
```

## What it does

Three screens.

```
src/
  app/
    (auth)/sign-in.tsx    Apple + Google; shown when there is no session
    (app)/index.tsx       home - the profile, and the way into editing it
    edit-profile.tsx      modal: photo and display name
  lib/
    auth.tsx              session + profile, Apple/Google, updateProfile
    avatar.ts             pick a photo, upload it, sweep the previous one
    supabase.ts           client; anon key only, RLS does the real work
    navigation.ts         back, or the screen's parent when there is no back
  theme.ts                Instrument Serif for display, Archivo for controls
```

## Auth and the database

Supabase, in its own project (not the weekly-rivals one — a schema change to one
must not be able to break the other). Sign in with Apple or Google; there is no
email/password path on purpose. Apple is first because App Review requires it
once any third-party sign-in is offered. The Google button hides itself until
both client IDs are set, so the app never shows an option guaranteed to throw.

Routing has two states: signed out, and in.

| table | who can read it |
| --- | --- |
| `profiles` | the owner |
| `avatars` bucket (Storage) | anyone — public read; writes confined to `<uid>/` |

Avatars are public-read because a profile picture is not a secret and a signed
URL per avatar would cost a round trip to render one. Write access is the part
that matters, and it is narrowed to the one folder named after the owner's uid.

Every upload gets a fresh filename. A fixed one is served stale from the CDN and
the device's image cache, so the owner would change their picture and watch the
old one persist; the previous objects are swept after each upload.

## Removed, and still in the database

The marketplace — brands, listings, photos, categories, the vision endpoint, the
eBay and Shopify adapters — was removed from the app. **Its tables are still
there**: `brands`, `listings`, `listing_channels`, `connections`,
`channel_credentials`, the `public_brands` view, and the `listing-photos` and
`brand-logos` buckets. Nothing reads them. They were left rather than dropped
because dropping is not reversible and the code is only a `git revert` away.

`profiles.username` is unused for the same reason — it was the storefront handle
before brands existed.

`supabase/seeds/demo_marketplace.sql` seeded five fake sellers as real auth
users. `demo_marketplace_down.sql` removes them.

The backend (`../snaplist-api`, deployed on Vercel) existed only to write
listings from a photograph. Nothing calls it now.

## Conventions

Matches `Projects/ios-app`: Expo SDK 57, expo-router, strict TypeScript, `@/*` →
`src/*`, no typed routes. Light theme on purpose.
