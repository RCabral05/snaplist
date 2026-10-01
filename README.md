# Snaplist

A native iPhone app for a personal, searchable archive: receipts, statements,
bills, warranties, manuals, and notes about where things are. Photograph or
import them; find them again by what they say.

Everything stays on the phone. There is no account and no server.

## Status

Phase 1 of the plan below: capture, local storage, on-device text recognition,
and search that leads back to the page a match was found on.

The previous Expo app (sign-in and a profile, backed by Supabase) was removed
on 2026-10-01 and is in git history before that.

## Building

You need a Mac with Xcode 26 or newer.

```
brew install xcodegen
xcodegen generate
open Snaplist.xcodeproj
```

The Xcode project is generated from `project.yml` and not committed. The
document camera does not exist in the simulator; use photos and files there,
or run on a device.

CI (`.github/workflows/ci.yml`) runs the core tests on Linux and builds the
app for the simulator on a hosted Mac, on every push.

The core package also builds and tests anywhere Swift 6 runs:

```
swift test --package-path Packages/ArchiveCore
```

## TestFlight

`.github/workflows/testflight.yml`, run by hand from the Actions tab, archives,
signs (automatic, cloud-managed) and uploads a build. Build numbers are
`1000 + run number`. It needs four repository secrets:

| Secret | What |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | the API key's ID |
| `APP_STORE_CONNECT_ISSUER_ID` | the issuer ID shown above the keys list |
| `APP_STORE_CONNECT_KEY` | the whole `.p8` file, including the BEGIN/END lines |
| `APPLE_TEAM_ID` | the 10-character team ID |

The key needs the Admin role (or App Manager with access to cloud-managed
distribution certificates) so Xcode can create the signing certificate.

## How it is put together

```
Packages/ArchiveCore/          plain Swift + SQLite; no Apple-only frameworks
  Model.swift                  Record, Asset (an original file), Page, TextLine
  ArchiveStore.swift           the database: schema, reads, writes, the index
  Search.swift                 full-text search, one hit per record, snippets
  ArchiveFiles.swift           originals on disk, one folder per record
  Archive.swift                adds and deletes across both, failing safe
  Ingestor.swift               pending record -> text -> ready (or failed)
Snaplist/
  App/                         app entry, AppModel (list, search, imports)
  Security/AppLock             Face ID / passcode lock, app-switcher cover
  Capture/DocumentScanner      VisionKit's document camera
  Extraction/                  Vision OCR, PDF text layer, page rendering
  Views/                       list + search, record detail, page view
```

**Storage.** SQLite through GRDB, not SwiftData: search needs FTS5 ranking
and spending totals (a later phase) need exact SQL sums, neither of which
SwiftData offers; and the store can be tested off-device. Originals are kept
byte-for-byte in Application Support with complete file protection, so they
cannot be read while the phone is locked.

**Text.** Images are read with Vision's `RecognizeTextRequest`, keeping each
line's position so matches can be highlighted on the page. A PDF page's own
text layer is used when it has one, and rendered and OCR'd when it does not.
OCR makes mistakes; the app says which text was machine-read.

**Import.** Originals are saved immediately and the record appears as
"Reading text…"; text is read in the background and the record becomes
searchable when it is done. A failure is kept on the record with a reason
and a retry, never silently dropped.

## Plan

1. Capture, storage, OCR, search with links to the page. *(this)*
2. Organise and correct: record types, dates, merchants, people, places;
   editing; voice notes with on-device transcription. (The Face ID / passcode
   lock from this phase is done.)
3. Receipt and statement extraction into transactions, with a review screen.
4. Questions with exact answers: totals computed in SQL from stored
   transactions, each answer citing the records it used. The on-device model
   (Foundation Models, where Apple Intelligence is available) only turns a
   question into a query; it never does arithmetic.
5. Possible duplicates (a receipt and its statement line), shown with the
   evidence, decided by the person.
6. Privacy and system: where data lives, export, delete everything, App
   Intents and Spotlight.

Later: iCloud sync, household sharing, a paid tier.
