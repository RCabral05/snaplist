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
    edit-profile.tsx      modal: photo, display name, username with a live check
  lib/
    auth.tsx              session + profile, Apple/Google, updateProfile
    avatar.ts             pick a photo, upload it, sweep the previous one
    supabase.ts           client; anon key only, RLS does the real work
    navigation.ts         back, or the screen's parent when there is no back
    use-handle-check.ts   debounced availability, with a stale-answer guard
  theme.ts                Instrument Serif for display, Archivo for controls
```

## Auth and the database

Supabase, in its own project (not the weekly-rivals one — a schema change to one
must not be able to break the other). Sign in with Apple or Google; there is no
email/password path on purpose. Apple is first because App Review requires it
once any third-party sign-in is offered. The Google button hides itself until
both client IDs are set, so the app never shows an option guaranteed to throw.

Routing has two states: signed out, and in. A username is optional and picked
whenever - there is no onboarding gate.

Availability needs `username_available()` and `claim_username()` as
security-definer RPCs because `profiles` is readable only by its owner: a
client-side "is this taken" query sees no rows and reports every name free.
Uniqueness is the index on `lower(username)`; case is preserved for display.

| table | who can read it |
| --- | --- |
| `profiles` | the owner |
| `username` | unique case-insensitively; claimed through two security-definer RPCs |
| `avatars` bucket (Storage) | anyone — public read; writes confined to `<uid>/` |

Avatars are public-read because a profile picture is not a secret and a signed
URL per avatar would cost a round trip to render one. Write access is the part
that matters, and it is narrowed to the one folder named after the owner's uid.

Every upload gets a fresh filename. A fixed one is served stale from the CDN and
the device's image cache, so the owner would change their picture and watch the
old one persist; the previous objects are swept after each upload.

## Removed

The marketplace - brands, listings, photos, categories, the vision endpoint, the
eBay and Shopify adapters - was removed from the app on 2026-09-27, and from the
database in migrations 0011 and 0012. What is left is `public.profiles`, the
`handle_new_user` trigger that fills it, and the `avatars` bucket.

A JSON snapshot of every dropped table was taken first and lives outside the
repo at `../snaplist-marketplace-snapshot-2026-09-27.json`; it contains seller
rows, so it is not committed.

Two dead buckets survive the migration: `listing-photos` (6 orphaned objects)
and `brand-logos` (empty). Supabase refuses direct deletes from storage tables -
rightly, since a row delete orphans the file rather than removing it - so they
have to go from the dashboard or the Storage API. Their policies are gone, so
nothing but the service role can reach them in the meantime.

The backend (`../snaplist-api`, deployed on Vercel) existed only to write
listings from a photograph. Nothing calls it now.

## Conventions

Matches `Projects/ios-app`: Expo SDK 57, expo-router, strict TypeScript, `@/*` →
`src/*`, no typed routes. Dark theme — the light-first rule existed to protect
product photographs, and those went with the marketplace.
